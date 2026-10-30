class Connecta::Runtime::ScopeActivationService
  class Conflict < StandardError; end

  # Contrato de fio v1 §10: conversas = display_id; account_id validado no
  # controller (403 se divergente). 409 em estado/versão divergente.
  def initialize(conversation_id:, attributes:)
    @conversation_display_id = Integer(conversation_id)
    @attributes = attributes
  end

  # Ativação com lock e idempotência no mesmo bloco; dividir separaria a checagem do lock.
  def call # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    expected_state = @attributes.fetch('expected_state').to_s
    raise Conflict, 'expected_state is invalid' unless %w[reception pending_activation].include?(expected_state)

    unit_id = @attributes.fetch('org_unit_id').to_s
    protocol = @attributes.fetch('case_protocol').to_s
    session_ref = @attributes.fetch('session_ref').to_s
    case_version = Integer(@attributes.fetch('case_version'))
    raise Conflict, 'activation fields are invalid' if unit_id.blank? || protocol.blank? || session_ref.blank? || case_version <= 0

    Connecta::ConversationScope.transaction do
      account_id = Connecta::Runtime::Feature.current_account_id!
      conversation = Conversation.find_by!(account_id: account_id, display_id: @conversation_display_id)
      scope = Connecta::ConversationScope.lock.find_by!(conversation_id: conversation.id)
      unit = Connecta::OrgUnit.find_by!(id: unit_id, enabled: true)
      # Saída antecipada por idempotência: nada foi escrito antes deste ponto, o retorno não desfaz trabalho.
      return idempotent_response(scope, unit_id, protocol, session_ref, case_version) if activated_as?(scope, unit_id, protocol, session_ref,
                                                                                                       case_version)
      raise Conflict, 'scope state changed' unless scope.state == expected_state

      if expected_state == 'pending_activation'
        activate_transfer!(scope, case_version)
      elsif case_version <= scope.case_version
        raise Conflict, 'case version must advance'
      end

      scope.update!(
        org_unit: unit, state: 'active', case_protocol: protocol, platform_session_ref: session_ref,
        case_version: case_version, activated_at: Time.current
      )
      { status: 'activated', conversation_id: @conversation_display_id, case_version: case_version }
    end
  rescue KeyError, ArgumentError, ActiveRecord::RecordNotFound => e
    raise Conflict, e.message
  end

  private

  def activated_as?(scope, unit_id, protocol, session_ref, version)
    scope.state == 'active' && scope.org_unit_id.to_s == unit_id && scope.case_protocol == protocol &&
      scope.platform_session_ref == session_ref && scope.case_version == version
  end

  def idempotent_response(scope, _unit_id, _protocol, _session_ref, version)
    { status: 'already_activated', conversation_id: @conversation_display_id, case_version: version } if scope.case_version == version
  end

  def activate_transfer!(scope, case_version)
    transfer = Connecta::TransferRecord.lock.find_by!(destination_conversation_id: scope.conversation_id)
    raise Conflict, 'transfer is not committed locally' unless transfer.state == 'committed_local' || transfer.state == 'committed'
    raise Conflict, 'case version mismatch' unless transfer.target_case_version == case_version

    transfer.update!(state: 'committed', committed_at: Time.current) if transfer.state == 'committed_local'
  end
end
