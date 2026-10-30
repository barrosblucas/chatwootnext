class Connecta::V1::AclController < Connecta::V1::BaseController
  # Contrato de fio v1 §8–§9: o guard de account_id roda no BaseController (403 se
  # divergente); sync vazio é heartbeat (só renova o heartbeat da ACL).
  rescue_from Connecta::Runtime::AclSyncService::InvalidProjection do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def sync
    render json: Connecta::Runtime::AclSyncService.new.call(payload.except('account_id'))
  end

  def revoke
    params = payload.except('account_id')
    result = Connecta::Runtime::AclRevocationService.new(
      user_id: params.fetch('chatwoot_user_id'), epoch: params.fetch('epoch'),
      revocation_id: params.fetch('revocation_id'), source: 'platform'
    ).call
    render json: { ack: { epoch: result.fetch(:epoch) }, revocation_id: result.fetch(:revocation_id) }
  rescue KeyError, ArgumentError, ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
