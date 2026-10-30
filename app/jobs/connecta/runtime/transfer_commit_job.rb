class Connecta::Runtime::TransferCommitJob < ApplicationJob
  queue_as :default
  retry_on Connecta::Runtime::PlatformClient::Error, wait: 10.seconds, attempts: 24

  # Commit e ativação em sequência com tratamento de falha por etapa; dividir mudaria o retry por estado.
  def perform(transfer_id) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    transfer = Connecta::TransferRecord.find(transfer_id)
    account_id = Connecta::Runtime::Feature.current_account_id!
    destination_conversation = Conversation.find(transfer.destination_conversation_id)
    if transfer.state == 'committed_local'
      response = Connecta::Runtime::PlatformClient.new.post(
        "/attendance/v1/transfers/#{transfer.id}/commit",
        transfer_id: transfer.id, account_id: account_id,
        destination_conversation_id: destination_conversation.display_id,
        committed_at: Time.current.iso8601, provider: 'chatwoot'
      )
      case_version = Integer(response.fetch('case_version'))
      origin = Connecta::Scope::ConversationScope.find_by!(conversation_id: transfer.source_conversation_id)
      local = Connecta::Transfer::LocalTransaction.new(
        scope: origin, destination_org_unit: Connecta::Scope::OrgUnit.find(transfer.destination_org_unit_id)
      )
      local.activate!(case_version: case_version)
      Connecta::Scope::ConversationScope.find_by!(conversation_id: transfer.destination_conversation_id)
                                        .update!(platform_session_ref: transfer.platform_session_ref)
      transfer.reload
    elsif transfer.state == 'committed'
      case_version = transfer.target_case_version
    else
      raise ActiveRecord::RecordNotFound, 'Transfer is not awaiting commit'
    end

    Connecta::Runtime::PlatformClient.new.post(
      "/attendance/v1/transfers/#{transfer.id}/activated", account_id: account_id, case_version: case_version
    )
    Connecta::Outbox.find_by!(dedupe_key: "transfer.committed:#{transfer.id}")
                    .update!(status: 'delivered', delivered_at: Time.current)
  rescue Connecta::Transfer::LocalTransaction::VersionMismatch => e
    local&.mark_stuck!
    transfer&.update!(state: 'activation_stuck')
    Connecta::Outbox.find_by(dedupe_key: "transfer.committed:#{transfer.id}")&.update!(status: 'failed')
    Rails.logger.error("Connecta transfer activation stuck transfer_id=#{transfer.id}: #{e.class}")
  rescue Connecta::Runtime::PlatformClient::Error => e
    raise e
  rescue ActiveRecord::RecordNotFound
    transfer&.update!(state: 'activation_stuck')
    raise
  end
end
