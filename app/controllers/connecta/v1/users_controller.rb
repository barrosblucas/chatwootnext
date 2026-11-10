class Connecta::V1::UsersController < Connecta::V1::BaseController
  # Fase 1 do vínculo simplificado (WP registra uma vez; fork provisiona o
  # agente via HMAC, sem código de pareamento). `account_id` é validado no
  # BaseController (403 se divergente de CONNECTA_ACCOUNT_ID).
  rescue_from Connecta::Provisioning::AgentProvisioner::ProvisionRejected do |error|
    render json: { error: 'provision_rejected', reason: error.reason }, status: :unprocessable_entity
  end

  rescue_from Connecta::Provisioning::AgentProvisioner::InvalidPassword do |error|
    render json: { error: 'invalid_password', reason: error.reason }, status: :unprocessable_entity
  end

  rescue_from Connecta::Provisioning::AgentProvisioner::NotAgent do
    render json: { error: 'not_agent' }, status: :conflict
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: 'not_found' }, status: :not_found
  end

  def provision
    result = provisioner.provision!(
      email: payload['email'],
      name: payload['name'],
      password: payload['password']
    )
    render json: result
  end

  def set_password
    provisioner.set_password!(user_id: params[:user_id], password: payload['password'])
    head :no_content
  end

  def deactivate
    if provisioner.deactivate!(user_id: params[:user_id])
      render json: { deactivated: true }
    else
      render json: { already_inactive: true }
    end
  end

  private

  def provisioner
    @provisioner ||= Connecta::Provisioning::AgentProvisioner.new(account: connecta_account)
  end

  def connecta_account
    Account.find(Connecta::Runtime::Feature.current_account_id!)
  end
end
