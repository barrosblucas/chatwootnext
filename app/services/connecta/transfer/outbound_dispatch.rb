# Despacho de saída do spike G0 (T0.7b). Cada mensagem de saída de inbox marcada tem uma linha em connecta_g0_outbound_dispatches.
# queued → dispatching só por UPDATE condicional com o escopo da conversa em active; sem isso a linha vira parked.
class Connecta::Transfer::OutboundDispatch
  class ConflictError < StandardError; end

  Result = Data.define(:parked, :wait)

  # Texto visível no Chatwoot quando o claim estaciona por falta de setor
  # (scope ausente, reception sem permissão, transferring). Manutenção NÃO usa
  # este texto (ver mark_parked_visible!): o fluxo de manutenção nega na
  # superfície HTTP (409) e o parked do claim é barreira temporária.
  PARKED_VISIBLE_ERROR = 'Mensagem não enviada: o atendimento ainda não tem setor definido (recepção) ou está em transferência.'.freeze

  # Uma instrução só: a troca de estado e a checagem do escopo acontecem juntas, então não há janela entre elas.
  # T3.9: em maintenance, o claim vira parked (não despacha); a superfície HTTP traduz em 409.
  # Recepção: libera só mensagem cujo remetente persistido (sender_type/sender_id
  # da linha messages, nunca content_attributes) é um usuário de serviço
  # configurado (CONNECTA_RECEPTION_SENDER_USER_IDS, vazio = nada liberado).
  CLAIM_SQL = <<~SQL.squish.freeze
    UPDATE connecta_g0_outbound_dispatches AS d
    SET state = CASE WHEN EXISTS (
          SELECT 1 FROM connecta_g0_conversation_scopes AS s
          JOIN connecta_g0_scoped_inboxes AS i ON i.inbox_id = s.inbox_id
          JOIN messages AS m ON m.id = d.message_id
          WHERE s.conversation_id = d.conversation_id
            AND i.maintenance = false AND i.enforcement <> 'maintenance'
            AND (s.state = 'active' OR (s.state = 'reception' AND m.sender_type = 'User' AND m.sender_id IN (?)))
        ) THEN 'dispatching' ELSE 'parked' END,
        attempted_at = now(), updated_at = now()
    WHERE d.message_id = ? AND d.state = 'queued'
    RETURNING d.state
  SQL

  class << self
    # Só mensagem de saída, não privada e ainda não enviada, de inbox marcada. Espelha os filtros de Base::SendOnChannelService.
    def dispatchable?(message)
      (message.outgoing? || message.template?) && !message.private? && message.source_id.blank? &&
        Connecta::Scope::ScopedInbox.exists?(inbox_id: message.inbox_id)
    end

    # Idempotente: insert com ON CONFLICT DO NOTHING. A linha nasce com a mensagem e o job a garante antes do claim.
    def enqueue!(message)
      return unless dispatchable?(message)

      # rubocop:disable Rails/SkipsModelValidations
      Connecta::Transfer::OutboundDispatchRecord.insert_all([{ message_id: message.id, conversation_id: message.conversation_id, state: 'queued' }])
      # rubocop:enable Rails/SkipsModelValidations
    end

    # Verdadeiro só para quem trocou queued por dispatching; com o escopo fora de active a linha vira parked.
    # Os ids de remetente entram como parâmetro (IN (?); vazio vira IN (NULL) e nunca libera a recepção).
    def claim!(message)
      state = Connecta::Transfer::OutboundDispatchRecord.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([CLAIM_SQL, Connecta::Runtime::Feature.reception_sender_user_ids, message.id])
      )
      state == 'dispatching'
    end

    # Parked visível: mensagem estacionada por falta de setor aparece como falha
    # no Chatwoot (status failed + external_error), para o agente ver e reenviar
    # depois da definição do setor. Manutenção NÃO marca: o fluxo de manutenção
    # nega na superfície HTTP (409) e o parked do claim é barreira temporária —
    # marcar failed quebraria esse fluxo (a mensagem pareceria erro do agente).
    def mark_parked_visible!(message)
      return if maintenance_parked?(message)

      Messages::StatusUpdateService.new(message, 'failed', PARKED_VISIBLE_ERROR).perform
    rescue StandardError => e
      Rails.logger.error("Connecta outbound dispatch could not mark parked message #{message.id} as failed: #{e.class}: #{e.message}")
    end

    def maintenance_parked?(message)
      inbox = Connecta::Scope::ScopedInbox.find_by(inbox_id: message.inbox_id)
      inbox.present? && inbox.maintenance_mode?
    end

    # Grava o resultado do conector. Nunca reenvia: só o claim tira uma linha de queued.
    def resolve!(message, state)
      Connecta::Transfer::OutboundDispatchRecord.find_by!(message_id: message.id).update!(state: state, connector_message_id: message.source_id)
    end

    # Início da transferência (escopo já transferring). Numa transação: com uncertain nada é parkeado.
    # Parkeia antes de ler dispatching/uncertain: um claim em andamento segura a linha até o commit, e a leitura depois dele o vê.
    def prepare_transfer!(conversation)
      Connecta::Transfer::OutboundDispatchRecord.transaction(requires_new: true) do
        rows = Connecta::Transfer::OutboundDispatchRecord.where(conversation_id: conversation.id)
        # update_all condicional: só mexe em queued, nunca em linha que já foi claimada.
        # rubocop:disable Rails/SkipsModelValidations
        parked = rows.where(state: 'queued').update_all(state: 'parked', updated_at: Time.current)
        # rubocop:enable Rails/SkipsModelValidations
        states = rows.where(state: %w[dispatching uncertain]).distinct.pluck(:state)
        raise ConflictError, "envio incerto na conversa #{conversation.id}: transferência retida até a conciliação" if states.include?('uncertain')

        Result.new(parked: parked, wait: states.include?('dispatching'))
      end
    end
  end

  # Prepend em Message: a linha queued nasce na criação da mensagem, antes do job, para prepare_transfer! enxergá-la.
  module MessageHook
    private

    def send_reply
      Connecta::Transfer::OutboundDispatch.enqueue!(self)
      super
    end
  end
end
