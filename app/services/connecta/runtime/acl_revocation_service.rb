class Connecta::Runtime::AclRevocationService
  # Contrato de fio v1 §9: ack {epoch} só após barreira local efetiva. Idempotente:
  # revogação já aplicada devolve o epoch vigente sem erro.
  def initialize(user_id:, epoch:, revocation_id:, source: 'platform')
    @user_id = Integer(user_id)
    @epoch = Integer(epoch)
    @revocation_id = revocation_id.to_s
    @source = source
  end

  # Fluxo único da barreira (lock, aplicação, broadcast); dividir espalharia a ordem de ack.
  def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    raise ArgumentError, 'revocation_id is required' if @revocation_id.blank?
    raise ArgumentError, 'epoch must be non-negative' if @epoch.negative?

    user = User.find(@user_id)
    applied_epoch = nil
    revoked_now = false
    Connecta::UserAuthEpoch.transaction do
      record = Connecta::UserAuthEpoch.lock.find_or_initialize_by(user_id: @user_id)
      # Revogação já aplicada no mesmo epoch (revoked_locally_at presente) é idempotente: ack sem reescrever.
      if record.new_record? || @epoch > record.epoch || (@epoch == record.epoch && record.revoked_locally_at.blank?)
        record.update!(epoch: @epoch, revoked_locally_at: Time.current, source: @source)
        revoked_now = true
      else
        revoked_now = false
      end
      applied_epoch = record.epoch
    end

    if revoked_now
      ActionCable.server.broadcast(user.pubsub_token, { event: 'acl.revoked', data: { user_id: user.id, epoch: applied_epoch } })
      disconnect_user_sockets!(user)
    end
    { epoch: applied_epoch, revocation_id: @revocation_id }
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  private

  def disconnect_user_sockets!(user)
    ActionCable.server.remote_connections.where(connecta_user_id: user.id.to_s).disconnect
  end
end
