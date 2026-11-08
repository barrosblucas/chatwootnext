class Api::V1::Accounts::Connecta::ProtocolsController < Api::V1::Accounts::BaseController
  # Protocolo é identificador operacional, não PII. Ausência, protocolo inválido
  # ou nenhuma etapa visível respondem o mesmo 404, sem revelar existência.
  def show
    result = Connecta::Scope::ProtocolView.call(
      account: Current.account, user: current_user, protocol: params[:protocol],
      cursor: params[:cursor], limit: params[:limit]
    )
    return head :not_found if result.nil?

    render json: result
  rescue Connecta::Scope::ProtocolView::InvalidRequest
    render json: { error: 'invalid_cursor' }, status: :unprocessable_entity
  end
end
