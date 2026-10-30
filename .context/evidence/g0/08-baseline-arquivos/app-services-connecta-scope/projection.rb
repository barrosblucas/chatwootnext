# Leituras frescas da projeção G0. Sem cache: revogação local vale na próxima requisição.
class Connecta::Scope::Projection
  HEARTBEAT_TTL = 5.minutes

  attr_reader :user

  def self.marked_inbox_ids
    Connecta::Scope::ScopedInbox.pluck(:inbox_id)
  end

  def self.marked?(inbox_id)
    Connecta::Scope::ScopedInbox.exists?(inbox_id: inbox_id)
  end

  def initialize(user)
    @user = user
  end

  def verified?
    Connecta::Scope::UserAuthEpoch.exists?(user_id: user.id, revoked_locally_at: nil)
  end

  def fresh?
    Connecta::Scope::AclSyncState.exists?(['last_heartbeat_at > ?', HEARTBEAT_TTL.ago])
  end

  def admin?
    verified? && Connecta::Scope::UserGrant.exists?(user_id: user.id, permission: 'admin_nominal')
  end

  def granted_paths(permissions)
    Connecta::Scope::UserGrant.joins(:org_unit)
                              .where(user_id: user.id, permission: permissions, connecta_g0_org_units: { enabled: true })
                              .pluck('connecta_g0_org_units.path')
  end
end
