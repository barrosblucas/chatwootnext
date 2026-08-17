class Api::V1::Accounts::Conversations::ConnectaTransfersController < Api::V1::Accounts::Conversations::BaseController
  def destinations
    render json: transfer_service.destinations
  rescue Connecta::TransferService::Error => e
    render json: { error: e.message }, status: e.status
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, HTTParty::Error
    render json: { error: I18n.t('errors.conversations.connecta_transfer.timeout') }, status: :gateway_timeout
  end

  def create
    render json: transfer_service.transfer(target_department_id: transfer_params[:target_department_id])
  rescue Connecta::TransferService::Error => e
    render json: { error: e.message }, status: e.status
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, HTTParty::Error
    render json: { error: I18n.t('errors.conversations.connecta_transfer.timeout') }, status: :gateway_timeout
  end

  private

  def transfer_service
    Connecta::TransferService.new(
      account: Current.account,
      conversation: @conversation,
      agent: Current.user
    )
  end

  def transfer_params
    params.permit(:target_department_id)
  end
end
