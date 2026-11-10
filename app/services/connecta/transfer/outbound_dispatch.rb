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

  class << self
    # SQL do claim com tabelas vivas (g0 no spike, produto em produção/com
    # G0Adapter ou no runner comum) + exceção Fase 2: a pesquisa CSAT
    # (input_csat, com protocolo) despacha com o escopo `closed`.
    def claim_sql
      dispatch_table = Connecta::Transfer::OutboundDispatchRecord.table_name

      <<~SQL.squish
        UPDATE #{dispatch_table} AS d
        SET state = CASE WHEN EXISTS (#{claim_scope_exists_sql}) THEN 'dispatching' ELSE 'parked' END,
          attempted_at = now(), updated_at = now()
        WHERE d.message_id = ? AND d.state = 'queued'
        RETURNING d.state
      SQL
    end

    def claim_scope_exists_sql
      scope_table = Connecta::Scope::CsatPolicy.scope_table_name
      inbox_table = Connecta::Scope::CsatPolicy.scoped_inbox_table_name
      csat_content_type = Message.content_types.fetch('input_csat')

      <<~SQL.squish
        SELECT 1 FROM #{scope_table} AS s
        JOIN #{inbox_table} AS i ON i.inbox_id = s.inbox_id
        JOIN messages AS m ON m.id = d.message_id
        WHERE s.conversation_id = d.conversation_id
          AND #{claim_enforcement_condition}
          AND (s.state = 'active' OR (s.state = 'reception' AND m.sender_type = 'User' AND m.sender_id IN (?))
               OR (s.state = 'closed' AND s.case_protocol IS NOT NULL AND s.case_protocol <> '' AND m.content_type = #{csat_content_type}))
      SQL
    end

    # Preserva a semântica de cada ambiente: no spike (g0) vale a condição
    # original (`<> 'maintenance'`); com tabelas de produto vale a do
    # G0Adapter (`= 'enforce'`). A exceção CSAT vale nos dois.
    def claim_enforcement_condition
      if Connecta::Transfer::OutboundDispatchRecord.table_name == 'connecta_g0_outbound_dispatches'
        "i.maintenance = false AND i.enforcement <> 'maintenance'"
      else
        "i.enforcement = 'enforce' AND i.maintenance = false"
      end
    end

    # Mensagem de saída/template, não privada, de inbox marcada. O source_id não
    # entra aqui: uma mensagem já enviada continua sendo gerenciada pelo Connecta
    # e o hook não pode reenviá-la pelo caminho nativo.
    def managed?(message)
      (message.outgoing? || message.template?) && !message.private? &&
        Connecta::Scope::ScopedInbox.exists?(inbox_id: message.inbox_id)
    end

    # Só mensagem gerenciada e ainda não enviada. Espelha os filtros de Base::SendOnChannelService.
    def dispatchable?(message)
      message.source_id.blank? && managed?(message)
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
    # Exceção Fase 2: a pesquisa CSAT (input_csat, com protocolo) despacha com o escopo `closed`.
    def claim!(message)
      state = Connecta::Transfer::OutboundDispatchRecord.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([claim_sql, Connecta::Runtime::Feature.reception_sender_user_ids, message.id])
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
    # Quando a pesquisa CSAT é aceita (criada e despachada), avisa o WP para
    # que ele interprete a nota digitada no WhatsApp (job com retry).
    def resolve!(message, state)
      Connecta::Transfer::OutboundDispatchRecord.find_by!(message_id: message.id).update!(state: state, connector_message_id: message.source_id)
      enqueue_csat_sent!(message) if state == 'accepted'
    end

    def enqueue_csat_sent!(message)
      return unless message.input_csat?
      return unless Connecta::Scope::CsatPolicy.scoped_inbox?(message.inbox_id)

      conversation = message.conversation
      return unless Connecta::Scope::CsatPolicy.final_protocol_resolution?(conversation)

      Connecta::Runtime::CsatSentJob.perform_later(message.id)
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
