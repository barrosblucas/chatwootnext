class Api::V1::Accounts::Conversations::ConnectaTransfersController < Api::V1::Accounts::Conversations::BaseController
  def destinations
    if Connecta::Runtime::Feature.enabled?
      Connecta::Runtime::TransferPolicy.new(conversation: @conversation, actor: current_user).authorize!
      account_id = Connecta::Runtime::Feature.current_account_id!
      query_params = {
        account_id: account_id, conversation_id: @conversation.display_id, actor_chatwoot_user_id: current_user.id
      }
      authority = native_authority(current_user, @conversation, account_id)
      query_params[:actor_authority] = authority unless authority.nil?
      query = URI.encode_www_form(query_params)
      response = Connecta::Runtime::PlatformClient.new.get("/attendance/v1/transfer-destinations?#{query}")
      render json: { destinations: transfer_destinations_list(response) }
    else
      proxy { transfer_service.destinations }
    end
  rescue Connecta::Runtime::TransferTransaction::Error, Connecta::Runtime::PlatformClient::Error => e
    render json: { error: e.message }, status: e.status
  end

  def create
    if Connecta::Runtime::Feature.enabled?
      result = Connecta::Runtime::TransferTransaction.new(
        account_id: Current.account.id,
        conversation: @conversation, actor: current_user,
        destination_org_unit_id: transfer_params[:target_org_unit_id], summary: transfer_params[:summary]
      ).call
      render json: result, status: :accepted
      return
    end

    target_department_id = transfer_params[:target_department_id]
    if target_department_id.blank?
      render json: { error: I18n.t('errors.conversations.connecta_transfer.target_department_id_required') },
             status: :unprocessable_entity
      return
    end

    proxy { transfer_service.transfer(target_department_id: target_department_id) }
  rescue Connecta::Runtime::TransferTransaction::Error, Connecta::Runtime::PlatformClient::Error => e
    # Contrato controlado: upstream inválido permanece 502 sem expor payload;
    # compensação remota (quando houve reserva) já foi enfileirada na transação,
    # nunca alegada como concluída aqui.
    render json: { error: e.message }, status: e.status
  end

  private

  def proxy
    render json: yield
  rescue Connecta::TransferService::Error, Connecta::Runtime::TransferTransaction::Error, Connecta::Runtime::PlatformClient::Error => e
    render json: { error: e.message }, status: e.status
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, HTTParty::Error
    render json: { error: I18n.t('errors.conversations.connecta_transfer.timeout') }, status: :gateway_timeout
  end

  def transfer_service
    Connecta::TransferService.new(
      account: Current.account,
      conversation: @conversation,
      agent: Current.user
    )
  end

  def transfer_params
    params.permit(:target_department_id, :target_org_unit_id, summary: [:subject, :completed, :next_action])
  end

  # WP devolve objeto { case_version, source_org_unit_id, destinations: [...], staff_user_id };
  # a API fork expõe só o array em { destinations: [...] }, com fallback seguro para [].
  def transfer_destinations_list(response)
    payload = response.is_a?(Hash) ? (response['destinations'] || response[:destinations]) : nil
    payload.is_a?(Array) ? payload : []
  end

  # F2: claim calculado no servidor a cada request; params/header/client nunca fornecem.
  def native_authority(actor, conversation, account_id)
    return nil unless conversation.account_id == account_id
    return Connecta::Runtime::TransferTransaction::NATIVE_AUTHORITY if Connecta::Scope::NativeAdmin.authorized_for?(actor, conversation)

    nil
  end
end
