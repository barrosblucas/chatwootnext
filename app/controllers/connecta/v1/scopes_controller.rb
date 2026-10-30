class Connecta::V1::ScopesController < Connecta::V1::BaseController
  # Contrato de fio v1 §10: display_id na rota; account_id validado no BaseController (403).
  rescue_from Connecta::Runtime::ScopeActivationService::Conflict do |error|
    render json: { error: error.message }, status: :conflict
  end

  def activate
    response = Connecta::Runtime::ScopeActivationService.new(
      conversation_id: params[:conversation_id], attributes: payload.except('account_id')
    ).call
    render json: response
  end
end
