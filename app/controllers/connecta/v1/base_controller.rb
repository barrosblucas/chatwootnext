class Connecta::V1::BaseController < ActionController::API
  before_action :authenticate_platform_request!
  before_action :require_configured_account!

  rescue_from Connecta::Runtime::HmacAuthenticator::InvalidSignature do |error|
    render json: { error: error.message }, status: :unauthorized
  end

  rescue_from Connecta::Runtime::AccountMismatch do |error|
    render json: { error: error.message }, status: :forbidden
  end

  private

  def authenticate_platform_request!
    Connecta::Runtime::HmacAuthenticator.new(secret: ENV.fetch('CONNECTA_PLATFORM_TO_FORK_SECRET', nil)).verify!(request)
  end

  # Contrato de fio v1: todo corpo/consulta carrega account_id (inteiro); o receptor
  # recusa com 403 se divergente da conta configurada (CONNECTA_ACCOUNT_ID). Campos
  # desconhecidos são ignorados.
  def require_configured_account!
    configured = Connecta::Runtime::Feature.current_account_id!
    provided = request_body_account_id || request.query_parameters[:account_id] || params[:account_id]
    Connecta::Runtime::AccountMismatch.check!(provided, configured)
  rescue ArgumentError
    raise Connecta::Runtime::AccountMismatch, 'account_id is required'
  end

  def request_body_account_id
    value = payload['account_id'] if payload.is_a?(Hash)
    value = nil if value.is_a?(Hash) || value.is_a?(Array)
    value
  end

  def payload
    request.request_parameters
  end
end
