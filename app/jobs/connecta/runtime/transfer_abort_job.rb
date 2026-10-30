class Connecta::Runtime::TransferAbortJob < ApplicationJob
  queue_as :default
  retry_on Connecta::Runtime::PlatformClient::Error, wait: 10.seconds, attempts: 24

  def perform(transfer_id, reason)
    account_id = Connecta::Runtime::Feature.current_account_id!
    Connecta::Runtime::PlatformClient.new.post(
      "/attendance/v1/transfers/#{transfer_id}/abort",
      account_id: account_id, reason: reason.to_s
    )
  rescue ArgumentError => e
    raise Connecta::Runtime::PlatformClient::Error.new(e.message, status: :service_unavailable)
  end
end
