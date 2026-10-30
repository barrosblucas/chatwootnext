class Api::V1::Accounts::Connecta::IdentityLinksController < Api::V1::Accounts::BaseController
  def create
    code = params.require(:code).to_s.strip
    raise ActionController::BadRequest, 'code is required' if code.blank? || code.length > 64

    response = Connecta::Runtime::PlatformClient.new.post(
      '/attendance/v1/identity-links/confirm',
      account_id: Connecta::Runtime::Feature.current_account_id!,
      chatwoot_user_id: current_user.id, code: code
    )
    render json: response
  rescue Connecta::Runtime::PlatformClient::Error => e
    render json: { error: e.message }, status: e.status
  end
end
