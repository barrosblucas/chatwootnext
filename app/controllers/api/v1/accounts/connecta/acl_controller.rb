class Api::V1::Accounts::Connecta::AclController < Api::V1::Accounts::BaseController
  # Fluxo da revogação de emergência (autorização, barreira, outbox, job) em uma ação; dividir espalha o ack.
  def emergency_revocations # rubocop:disable Metrics/AbcSize
    projection = Connecta::Scope::Projection.new(current_user)
    raise Pundit::NotAuthorizedError unless projection.admin?

    result = Connecta::Runtime::AclRevocationService.new(
      user_id: params.require(:chatwoot_user_id), epoch: params.require(:epoch),
      revocation_id: SecureRandom.uuid, source: 'emergency'
    ).call
    Connecta::Outbox.create_or_find_by!(dedupe_key: "acl.emergency-revocation:#{params[:chatwoot_user_id]}:#{result.fetch(:epoch)}") do |outbox|
      outbox.event_type = 'acl.emergency-revocation'
      outbox.payload = { user_id: params[:chatwoot_user_id], actor_user_id: current_user.id,
                         epoch: result.fetch(:epoch), revocation_id: result.fetch(:revocation_id) }
    end
    Connecta::Runtime::EmergencyRevocationJob.perform_later(
      params[:chatwoot_user_id], current_user.id, result.fetch(:epoch), result.fetch(:revocation_id)
    )
    render json: { status: 'revocation_pending', epoch: result.fetch(:epoch) }, status: :accepted
  rescue Pundit::NotAuthorizedError
    render json: { error: 'Admin nominal permission required' }, status: :forbidden
  end
end
