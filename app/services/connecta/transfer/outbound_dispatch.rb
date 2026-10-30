# Despacho de saída do spike G0 (T0.7b). Cada mensagem de saída de inbox marcada tem uma linha em connecta_g0_outbound_dispatches.
# queued → dispatching só por UPDATE condicional com o escopo da conversa em active; sem isso a linha vira parked.
class Connecta::Transfer::OutboundDispatch
  class ConflictError < StandardError; end

  Result = Data.define(:parked, :wait)

  # Uma instrução só: a troca de estado e a checagem do escopo acontecem juntas, então não há janela entre elas.
  # T3.9: em maintenance, o claim vira parked (não despacha); a superfície HTTP traduz em 409.
  CLAIM_SQL = <<~SQL.squish.freeze
    UPDATE connecta_g0_outbound_dispatches AS d
    SET state = CASE WHEN EXISTS (
          SELECT 1 FROM connecta_g0_conversation_scopes AS s
          JOIN connecta_g0_scoped_inboxes AS i ON i.inbox_id = s.inbox_id
          WHERE s.conversation_id = d.conversation_id AND s.state = 'active'
            AND i.maintenance = false AND i.enforcement <> 'maintenance'
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
    def claim!(message)
      state = Connecta::Transfer::OutboundDispatchRecord.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([CLAIM_SQL, message.id])
      )
      state == 'dispatching'
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
