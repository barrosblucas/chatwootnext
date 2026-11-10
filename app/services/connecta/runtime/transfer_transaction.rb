class Connecta::Runtime::TransferTransaction
  SUMMARY_LIMITS = { subject: 160, completed: 2000, next_action: 2000 }.freeze
  # F2: único valor de claim aceito pelo WP (contrato de fio v1, extensão opcional).
  NATIVE_AUTHORITY = 'chatwoot_account_admin'.freeze
  DEFAULT_DISPATCH_WAIT_MS = 5_000
  MAX_DISPATCH_WAIT_MS = 30_000

  class Error < StandardError
    attr_reader :status

    def initialize(message, status: :unprocessable_entity)
      @status = status
      super(message)
    end
  end

  def initialize(conversation:, actor:, destination_org_unit_id:, summary:, account_id: nil)
    @conversation = conversation
    @actor = actor
    @destination_org_unit_id = destination_org_unit_id.to_s
    @summary = normalize_summary(summary)
    @account_id = account_id.nil? ? Connecta::Runtime::Feature.current_account_id! : Integer(account_id)
    @client = Connecta::Runtime::PlatformClient.new
  rescue ArgumentError
    raise Error.new('account_id is invalid', status: :service_unavailable)
  end

  def call
    source = Connecta::Runtime::TransferPolicy.new(conversation: @conversation, actor: @actor).authorize!
    local = build_local_transaction(source)
    prepared = { remote: false }
    transfer, target_version = prepare_transfer!(local, source, prepared)

    commit_local_destination!(local, transfer, source, target_version)
  rescue Connecta::Runtime::PlatformClient::Error => e
    handle_platform_failure!(local, e)
  rescue Connecta::Transfer::OutboundDispatch::ConflictError
    # Falha antes do prepare remoto ⇒ sem abort remoto.
    abort_local_prepare!(local, notify_remote: false, reason: 'dispatch_conflict')
    raise Error.new('Outbound message is uncertain; transfer is held for reconciliation', status: :conflict)
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique => e
    # §4: transação local falhou/desfeita após prepare bem-sucedido ⇒ abort remoto via job.
    abort_local_prepare!(local, notify_remote: prepared&.dig(:remote), reason: local_reason(prepared, 'prepare_local_conflict'))
    raise Error.new(e.message, status: :conflict)
  rescue KeyError, ArgumentError, TypeError => e
    abort_local_prepare!(local, notify_remote: prepared&.dig(:remote), reason: local_reason(prepared, 'prepare_payload_invalid'))
    raise Error.new(e.message, status: :unprocessable_entity)
  rescue Error => e
    # Erro de domínio após HTTP 200 (ex.: versão inválida do prepare) ou após
    # reconciliação: compensa a reserva remota quando ela pode existir e relança
    # sem mascarar o status (502 para upstream inválido permanece 502).
    abort_local_prepare!(local, notify_remote: prepared&.dig(:remote) || false, reason: local_reason(prepared, 'prepare_payload_invalid'))
    raise
  end

  private

  def handle_platform_failure!(local, error)
    if %i[gateway_timeout bad_gateway service_unavailable].include?(error.status)
      reconcile_unknown_prepare!(local)
      raise Error.new(error.message, status: error.status)
    end
    # §4: a plataforma nunca reservou (prepare recusado) ⇒ sem abort remoto.
    abort_local_prepare!(local, notify_remote: false, reason: 'prepare_failed')
    raise Error.new(error.message, status: error.status)
  end

  # prepared é nil quando a falha ocorre antes de prepare_transfer! (ex.: unidade de destino ausente).
  def local_reason(prepared, fallback)
    prepared&.dig(:remote) ? 'local_failure' : fallback
  end

  # Valida o destino antes de qualquer efeito local ou remoto (mesma ordem de antes).
  def build_local_transaction(source)
    if @destination_org_unit_id.blank? || @destination_org_unit_id == source.org_unit_id.to_s
      raise Error.new('Choose a different destination unit', status: :unprocessable_entity)
    end

    destination_unit = Connecta::Scope::OrgUnit.find_by(id: @destination_org_unit_id, enabled: true)
    raise Error.new('Destination unit is not synchronized', status: :unprocessable_entity) unless destination_unit

    Connecta::Transfer::LocalTransaction.new(scope: source, destination_org_unit: destination_unit, retain_uncertain: true)
  end

  def summary_fingerprint
    summary_json = @summary.to_json
    [Digest::SHA256.hexdigest(summary_json), summary_json.bytesize]
  end

  # Ordem preservada: fingerprint, begin/record local, prepare remoto (marca prepared[:remote]
  # imediatamente após HTTP 200, ANTES de validar o payload: resposta bem-sucedida
  # mas malformada pode já ter reservado no WP e exige compensação).
  def prepare_transfer!(local, source, prepared)
    summary_hash, summary_length = summary_fingerprint
    transfer = begin_local_transfer!(local, source, summary_hash, summary_length)
    target_version = prepare_remote!(transfer, source, summary_hash, summary_length, prepared)
    [transfer, target_version]
  end

  def begin_local_transfer!(local, source, summary_hash, summary_length)
    begin_result = local.begin!
    begin_result = wait_for_dispatch(local, begin_result)
    raise Error.new('Outbound message is still being reconciled', status: :conflict) if begin_result == Connecta::Transfer::LocalTransaction::HELD
    raise Error.new('Outbound message is still dispatching', status: :conflict) if begin_result == Connecta::Transfer::LocalTransaction::WAIT

    transfer = local.record
    if transfer.summary_sha256.present? && transfer.summary_sha256 != summary_hash
      raise Error.new('An existing transfer for this conversation has a different summary', status: :conflict)
    end

    transfer.update!(
      state: 'prepared', source_org_unit_id: source.org_unit_id, destination_org_unit_id: @destination_org_unit_id,
      actor_user_id: @actor.id, summary_sha256: summary_hash, summary_length: summary_length, prepared_at: Time.current
    )
    transfer
  end

  # Contrato de fio v1: WP guarda a versão de origem no prepare e incrementa uma vez
  # sob lock no commit; fork deriva alvo=origem+1. Resposta de prepare bem-sucedida
  # devolve a MESMA versão enviada (eco da origem); commit/activated exigem o alvo
  # exato (commit_local! + activate! conferem igualdade). Resposta ausente,
  # não-numérica ou divergente é erro controlado 502 sem expor o payload.
  def prepare_remote!(transfer, source, summary_hash, summary_length, prepared = nil)
    payload = {
      transfer_id: transfer.id, account_id: @account_id, conversation_id: @conversation.display_id,
      case_protocol: source.case_protocol, case_version: source.case_version,
      destination_org_unit_id: @destination_org_unit_id,
      actor_chatwoot_user_id: @actor.id, summary_sha256: summary_hash, summary_length: summary_length
    }
    authority = native_authority
    payload[:actor_authority] = authority unless authority.nil?
    response = @client.post('/attendance/v1/transfers/prepare', payload)
    # HTTP 200 ⇒ reserva potencial no WP mesmo com corpo inválido: marca ANTES de validar.
    prepared[:remote] = true if prepared
    begin
      raise Error.new('Platform returned an invalid case version', status: :bad_gateway) unless response.is_a?(Hash)

      response_version = Integer(response.fetch('case_version'))
    rescue KeyError, TypeError, ArgumentError
      raise Error.new('Platform returned an invalid case version', status: :bad_gateway)
    end
    unless response_version == source.case_version
      raise Error.new('Platform returned an invalid case version', status: :bad_gateway)
    end

    target_version = source.case_version + 1
    transfer.update!(state: 'prepared', target_case_version: target_version, platform_session_ref: response['to_session_ref'])
    target_version
  end

  def commit_local_destination!(local, transfer, source, target_version)
    destination = local.commit_local!(target_case_version: target_version, summary: @summary.values.join("\n\n"))
    if destination == Connecta::Transfer::LocalTransaction::WAIT || destination == Connecta::Transfer::LocalTransaction::HELD
      raise Error.new('Outbound message is still being reconciled', status: :conflict)
    end

    destination_scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: destination.id)
    destination_scope.update!(transfer_id: transfer.id, platform_session_ref: transfer.platform_session_ref)
    announce_scope_revoked(source, transfer)
    Connecta::Outbox.create!(
      dedupe_key: "transfer.committed:#{transfer.id}", event_type: 'transfer.committed',
      payload: {
        transfer_id: transfer.id, conversation_id: @conversation.display_id,
        destination_conversation_id: destination.display_id
      }
    )
    Connecta::Runtime::TransferCommitJob.perform_later(transfer.id)

    { status: 'pending_activation', transfer_id: transfer.id, source_conversation_id: @conversation.display_id }
  end

  # O announce é só notificação de UI: nunca aborta o commit já gravado.
  def announce_scope_revoked(source, transfer)
    Connecta::Runtime::CacheRevocation.scope!(source)
  rescue StandardError => e
    Rails.logger.warn("[connecta] scope.revoked announce failed transfer_id=#{transfer.id}: #{e.class}")
  end

  def normalize_summary(input)
    raise Error, 'Summary is required' unless input.is_a?(ActionController::Parameters) || input.is_a?(Hash)

    values = {
      subject: input['subject'] || input[:subject],
      completed: input['completed'] || input[:completed],
      next_action: input['next_action'] || input[:next_action]
    }
    values.each { |key, value| values[key] = normalize_summary_value(key, value) }
    values
  end

  def normalize_summary_value(key, value)
    normalized = value.to_s.strip
    raise Error, "#{key} is required" if normalized.blank?
    raise Error, "#{key} exceeds #{SUMMARY_LIMITS.fetch(key)} characters" if normalized.length > SUMMARY_LIMITS.fetch(key)

    normalized
  end

  def wait_for_dispatch(local, result)
    return result unless result == Connecta::Transfer::LocalTransaction::WAIT

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (dispatch_wait_ms / 1000.0)
    while result == Connecta::Transfer::LocalTransaction::WAIT && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.1
      result = local.resume!
    end
    result
  end

  def dispatch_wait_ms
    configured = Integer(ENV.fetch('CONNECTA_DISPATCH_WAIT_MS', DEFAULT_DISPATCH_WAIT_MS.to_s))
    return configured if configured.between?(0, MAX_DISPATCH_WAIT_MS)

    raise Error.new("CONNECTA_DISPATCH_WAIT_MS must be between 0 and #{MAX_DISPATCH_WAIT_MS}", status: :service_unavailable)
  rescue ArgumentError
    raise Error.new('CONNECTA_DISPATCH_WAIT_MS must be an integer', status: :service_unavailable)
  end

  def reconcile_unknown_prepare!(local)
    transfer = local&.record
    return unless transfer&.persisted?

    transfer.update!(state: 'unknown')
  rescue ActiveRecord::RecordNotFound
    nil
  end

  # F2: claim recalculado no servidor a cada prepare; params/header/client nunca fornecem.
  def native_authority
    return nil unless @conversation.account_id == @account_id
    return NATIVE_AUTHORITY if Connecta::Scope::NativeAdmin.authorized_for?(@actor, @conversation)

    nil
  end

  # Contrato de fio v1 §4: quando a transação local falha ou é desfeita após
  # prepare bem-sucedido, o fork DEVE chamar abort na plataforma (via job com retry).
  def abort_local_prepare!(local, notify_remote:, reason:)
    transfer = local&.record
    return unless transfer&.persisted?

    local.abort!
    return unless notify_remote

    Connecta::Runtime::TransferAbortJob.perform_later(transfer.id, reason)
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
