class Connecta::Runtime::EmergencyRevocationJob < ApplicationJob
  queue_as :default
  retry_on Connecta::Runtime::PlatformClient::Error, wait: 10.seconds, attempts: 24

  def perform(user_id, actor_user_id, epoch, revocation_id)
    account_id = Connecta::Runtime::Feature.current_account_id!
    Connecta::Runtime::PlatformClient.new.post(
      '/attendance/v1/acl/emergency-revocations',
      account_id: account_id, chatwoot_user_id: user_id, actor_user_id: actor_user_id, epoch: epoch,
      revocation_id: revocation_id
    )
    Connecta::Outbox.find_by!(dedupe_key: "acl.emergency-revocation:#{user_id}:#{epoch}")
                    .update!(status: 'delivered', delivered_at: Time.current)
  end
end
