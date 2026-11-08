# Ciclo de vida do escopo Connecta na resolução/reabertura (decisão 005).
# Quando a conversa de inbox marcada é RESOLVIDA pelo operador, o escopo ativo
# vai ao estado terminal `closed` (mantém setor/protocolo/versão/histórico).
# Mensagem nova do cidadão nunca reabre: com o escopo fora de NON_TERMINAL, o
# IncomingHook e o ConversationReuse caem no fluxo nativo, que com
# lock_to_single_conversation=false cria conversa nova (esta ganha `reception`
# via ReceptionScopeCreator e o bot envia o menu). Reabertura explícita
# (resolved→open pelo toggle_status) restaura o MESMO atendimento a `active`
# (ou `reception`, quando nunca foi ativado: case_version zero).
# Escrita em conversa resolvida é negada pelo guard HTTP, inclusive para
# administrador nativo e usuário de serviço; leitura continua permitida
# (`closed` está em READ_STATES). Tudo protegido pela flag de runtime
# (CONNECTA_HUMAN_NUMBER_ENABLED) + inbox marcada; fora disso, nativo.
# Sem migração: a coluna `state` não tem CHECK no banco (só validação no
# modelo) e o índice parcial único cobre só NON_TERMINAL, de modo que
# `closed` já é terminal (não reutilizável, sem conflito de unicidade).
class Connecta::Scope::ConversationResolution
  CLOSED_STATE = 'closed'.freeze

  class << self
    # Reação a mudança de status já salva (after_update_commit). Entrada em
    # resolved fecha o escopo; saída de resolved para open reabre o mesmo
    # atendimento. Outras transições não tocam o escopo. Idempotente.
    def after_conversation_status_commit(conversation)
      return unless lifecycle_enforced?(conversation)

      change = conversation.saved_change_to_status?
      return unless change

      old_status, _new_status = conversation.saved_change_to_status
      if conversation.resolved?
        resolve_scope!(conversation)
      elsif conversation.open? && old_status == 'resolved'
        reopen_scope!(conversation)
      end
    rescue StandardError => e
      Rails.logger.error("Connecta resolution sync failed for conversation #{conversation.id}: #{e.class}: #{e.message}")
    end

    # Resolve → terminal. Fecha os estados estáveis (`reception`, `active`) e
    # também os transitórios da transferência, sob o lock do par para não correr
    # com begin!/commit_local!:
    # - `transferring`: aborta o preparo pré-commit e fecha a origem; sem isso,
    #   um inbound novo encontraria o escopo não-terminal e cairia na conversa
    #   resolvida (ou colidiria no índice único do par).
    # - `pending_activation`: destino já commitado; fecha e marca o transfer
    #   como `activation_stuck`, para a ativação tardia não reabrir sozinha.
    # - `activation_stuck`: fecha direto.
    # Mantém org_unit/case_protocol/case_version; carimba closed_at. Sem escopo
    # (conversa legada) ou já terminal: nada faz.
    def resolve_scope!(conversation) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
      return unless lifecycle_enforced?(conversation)

      remote_abort_ids = []
      ActiveRecord::Base.transaction do
        Connecta::Transfer::LocalTransaction.lock!(
          inbox_id: conversation.inbox_id, contact_id: conversation.contact_id
        )
        scope = Connecta::Scope::ConversationScope.lock.find_by(conversation_id: conversation.id)
        next if scope.nil? || terminal_scope_state?(scope.state)

        case scope.state
        when 'reception', 'active', 'activation_stuck'
          close_scope!(scope)
        when 'transferring'
          remote_abort_ids = abort_inflight_transfer!(scope)
        when 'pending_activation'
          close_pending_activation!(scope)
        end
      end
      remote_abort_ids.each do |transfer_id|
        # Pode rodar dentro da transação do IncomingHook: só enfileira depois
        # de TODAS as transações da conexão commitarem. Em rollback o callback
        # é descartado e o abort remoto não é disparado.
        ActiveRecord.after_all_transactions_commit do
          Connecta::Runtime::TransferAbortJob.perform_later(transfer_id, 'conversation_resolved')
        end
      end
    end

    # Reabertura explícita do operador → volta ao atendimento anterior.
    # Com versão de caso (>0) volta a `active`; sem ativação (versão zero)
    # volta a `reception`. Se já existir atendimento não-terminal mais novo do
    # mesmo par (inbox, contato), mantém `closed` e só registra: reabrir criaria
    # dois atendimentos não-terminais e violaria o índice parcial único. Nesse
    # caso o operador resolve o duplicado manualmente (opção documentada: permitir
    # sem bloquear, sem erro 500).
    def reopen_scope!(conversation)
      return unless lifecycle_enforced?(conversation)

      scope = Connecta::Scope::ConversationScope.find_by(conversation_id: conversation.id)
      return if scope.nil?
      return unless scope.state == CLOSED_STATE

      if newer_open_scope_exists?(scope)
        Rails.logger.warn("Connecta resolution reopen kept closed for conversation #{conversation.id}: newer non-terminal scope exists")
        return
      end

      scope.update!(state: scope.case_version.positive? ? 'active' : 'reception', closed_at: nil)
    rescue ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("Connecta resolution reopen kept closed for conversation #{conversation.id}: #{e.message}")
    end

    # Guarda de reabertura automática nativa (Message#reopen_resolved_conversation):
    # em inbox marcada com runtime ligado, a mensagem entrante nunca reabre a
    # conversa resolvida (o fluxo de entrada já criou conversa nova).
    def auto_reopen_blocked?(conversation)
      lifecycle_enforced?(conversation)
    end

    private

    def close_scope!(scope)
      scope.update!(state: CLOSED_STATE, closed_at: Time.current)
    end

    # Só registros pré-commit são abortáveis. Se o transfer já commitou, a
    # origem deveria estar transferred_out (terminal) e o caso não chega aqui.
    def abort_inflight_transfer!(scope)
      remote_ids = []
      if transfer_records_available?
        records = Connecta::Transfer::TransferRecord.where(
          source_conversation_id: scope.conversation_id,
          state: %w[requested awaiting_dispatch prepared unknown]
        ).to_a
        remote_ids = records.select do |record|
          %w[prepared unknown].include?(record.state) &&
            record.has_attribute?('platform_session_ref') &&
            record.platform_session_ref.present?
        end.map(&:id)
        records.each { |record| record.update!(state: 'aborted') }
      end
      close_scope!(scope)
      remote_ids
    end

    # O destino já pertence a um transfer commitado; fechar sem marcar o
    # registro permitiria uma ativação tardia em conversa resolvida.
    def close_pending_activation!(scope)
      if transfer_records_available?
        Connecta::Transfer::TransferRecord.where(
          destination_conversation_id: scope.conversation_id,
          state: 'committed_local'
        ).find_each { |record| record.update!(state: 'activation_stuck') }
      end
      close_scope!(scope)
    end

    def transfer_records_available?
      Connecta::Transfer::TransferRecord.table_exists?
    rescue StandardError
      false
    end

    def lifecycle_enforced?(conversation)
      Connecta::Runtime::Feature.enabled? && Connecta::Scope::Projection.marked?(conversation.inbox_id)
    rescue StandardError
      false
    end

    def terminal_scope_state?(state)
      state == CLOSED_STATE || state == 'transferred_out'
    end

    def newer_open_scope_exists?(scope)
      Connecta::Scope::ConversationScope
        .where(inbox_id: scope.inbox_id, contact_id: scope.contact_id, state: Connecta::Scope::ConversationScope::NON_TERMINAL_STATES)
        .where.not(conversation_id: scope.conversation_id)
        .exists?
    end
  end

  # Prepend em Message: bloqueia a reabertura automática de conversa resolvida
  # em inbox marcada (o entrante segue em conversa nova pelo fluxo nativo).
  # Snoozed→open e inbox não marcada seguem nativos.
  module MessageHook
    def reopen_resolved_conversation
      return if Connecta::Scope::ConversationResolution.auto_reopen_blocked?(conversation)

      super
    end
  end

  # Hook de callback de status (registrado pelo Installer via after_update_commit).
  module ConversationHook
    def connecta_resolution_after_status_change
      Connecta::Scope::ConversationResolution.after_conversation_status_commit(self)
    end
  end
end
