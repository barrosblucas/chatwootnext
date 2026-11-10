# Leituras frescas da projeção G0. Sem cache: revogação local vale na próxima requisição.
class Connecta::Scope::Projection
  # Fonte única do TTL de heartbeat (mesma env que o adapter G0). Padrão 120 s = 3 × 40 s, o intervalo de envio do WP
  # com aclHeartbeatMaxAgeSec=120 (apps/whatsapp-platform/src/config.ts:156; envio em humanService/runtime.ts:62).
  DEFAULT_HEARTBEAT_TTL_SEC = 120
  # Janela de graça B5: entre o TTL e TTL + graça, o fork segue usando os
  # últimos grants aplicados (modo degradado) em vez de negar tudo durante um
  # deploy/outage do WP. Padrão 900 s; 0 desliga (fail-closed direto no TTL).
  DEFAULT_STALE_GRACE_SEC = 900

  attr_reader :user

  def self.heartbeat_ttl
    Integer(ENV.fetch('CONNECTA_ACL_HEARTBEAT_TTL_SEC', DEFAULT_HEARTBEAT_TTL_SEC.to_s)).seconds
  end

  def self.stale_grace
    Integer(ENV.fetch('CONNECTA_ACL_STALE_GRACE_SEC', DEFAULT_STALE_GRACE_SEC.to_s)).seconds
  end

  def self.marked_inbox_ids
    Connecta::Scope::ScopedInbox.pluck(:inbox_id)
  end

  def self.marked?(inbox_id)
    Connecta::Scope::ScopedInbox.exists?(inbox_id: inbox_id)
  end

  def initialize(user)
    @user = user
  end

  # Memoização por instância (uma por Gate/request): a mesma resposta serve
  # todas as etapas do protocolo sem repetir UserGrant/OrgUnit por linha.
  def verified?
    return @verified if defined?(@verified)

    @verified = Connecta::Scope::UserAuthEpoch.exists?(user_id: user.id, revoked_locally_at: nil)
  end

  def fresh?
    return @fresh if defined?(@fresh)

    @fresh = Connecta::Scope::AclSyncState.exists?(['last_heartbeat_at > ?', self.class.heartbeat_ttl.ago])
  end

  # Modo degradado B5: heartbeat além do TTL mas ainda dentro de TTL + graça.
  # Só o heartbeat conta aqui; usuário revogado continua negado via usable?.
  def degraded?
    return @degraded if defined?(@degraded)

    @degraded = !fresh? && heartbeat_usable?
  end

  # Decisão única de frescor para Gate e ConversationQuery: verificado (não
  # revogado) E heartbeat dentro de TTL + graça. Depois da graça, fail-closed.
  def usable?
    return @usable if defined?(@usable)

    @usable = verified? && heartbeat_usable?
    Rails.logger.warn("connecta_acl_degraded user_id=#{user.id}") if @usable && degraded?
    @usable
  end

  def admin?
    return @admin if defined?(@admin)

    @admin = verified? && Connecta::Scope::UserGrant.exists?(user_id: user.id, permission: 'admin_nominal')
  end

  def granted_paths(permissions)
    @granted_paths ||= {}
    key = Array(permissions).map(&:to_s).sort.freeze
    @granted_paths[key] ||= Connecta::Scope::UserGrant.joins(:org_unit)
                                                      .where(user_id: user.id, permission: permissions,
                                                             connecta_g0_org_units: { enabled: true })
                                                      .pluck('connecta_g0_org_units.path')
                                                      .freeze
  end

  private

  def heartbeat_usable?
    window = self.class.heartbeat_ttl + self.class.stale_grace
    Connecta::Scope::AclSyncState.exists?(['last_heartbeat_at > ?', window.ago])
  rescue ArgumentError
    false
  end
end
