class Connecta::Scope::AssignmentPolicy
  class << self
    # Shared target rule, the single definition mirrored from #allowed? lines
    # 13-14: usable projection (verified epoch + fresh heartbeat) and an
    # `atender` grant covering the unit path. Every assign surface (endpoint
    # listing, POST assignments, macros/automation, builder) funnels through
    # here so the rule cannot drift between surfaces.
    def target_eligible?(account:, org_unit:, target_id:)
      return false if target_id.blank? || org_unit.nil? || !org_unit.enabled?

      target = account.users.find_by(id: target_id)
      return false unless target

      projection = Connecta::Scope::Projection.new(target)
      projection.usable? && covers_unit?(projection, org_unit, 'atender')
    end

    # Bulk version of the same rule: { org_unit_id => [user_id] } of eligible
    # targets per unit (keyed by id so callers never depend on record
    # identity). Per-user work is one verified? + one heartbeat + one
    # grants query, independent of the unit count.
    def eligible_target_ids_by_unit(account:, org_units:)
      units = Array(org_units).select { |unit| unit.present? && unit.enabled? }
      by_unit = units.to_h { |unit| [unit.id, []] }
      return by_unit if units.empty?

      paths_by_user = atender_paths_by_user(account)
      return by_unit if paths_by_user.nil?

      paths_by_user.each do |user_id, paths|
        units.each do |unit|
          by_unit[unit.id] << user_id if paths.any? { |path| unit.path.start_with?(path) }
        end
      end
      by_unit
    end

    private

    # nil when the global heartbeat is not usable: mirrors
    # Projection#usable? fail-closed (nobody is eligible on a stale ACL).
    def atender_paths_by_user(account)
      return nil unless heartbeat_usable?

      verified_ids = Connecta::Scope::UserAuthEpoch.where(user_id: account.users.select(:id),
                                                           revoked_locally_at: nil).pluck(:user_id)
      return {} if verified_ids.empty?

      unit_table = Connecta::Scope::OrgUnit.quoted_table_name
      rows = Connecta::Scope::UserGrant.joins(:org_unit)
                                       .where(user_id: verified_ids, permission: 'atender')
                                       .where("#{unit_table}.#{Connecta::Scope::OrgUnit.connection.quote_column_name('enabled')} = ?",
                                              true)
                                       .pluck(:user_id, "#{unit_table}.#{Connecta::Scope::OrgUnit.connection.quote_column_name('path')}")
      rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(user_id, path), memo|
        memo[user_id] << path
      end
    end

    # Mirrors Projection#heartbeat_usable?: TTL + grace window, fail-closed.
    def heartbeat_usable?
      window = Connecta::Scope::Projection.heartbeat_ttl + Connecta::Scope::Projection.stale_grace
      Connecta::Scope::AclSyncState.exists?(['last_heartbeat_at > ?', window.ago])
    rescue ArgumentError
      false
    end

    def covers_unit?(projection, org_unit, permission)
      projection.granted_paths([permission]).any? { |path| org_unit.path.start_with?(path) }
    end
  end

  def initialize(conversation:, actor:, target_id:, target_type:)
    @conversation = conversation
    @actor = actor
    @target_id = target_id.presence
    @target_type = target_type
  end

  def allowed? # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return false if @target_type.to_s == 'AgentBot'

    scope = Connecta::Scope::ConversationScope.includes(:org_unit).find_by(conversation_id: @conversation.id)
    return false unless scope&.org_unit&.enabled?
    return false if @target_id && !eligible_target?(scope)

    return true if Connecta::Scope::NativeAdmin.authorized_for?(@actor, @conversation)

    projection = Connecta::Scope::Projection.new(@actor)
    return false unless projection.usable?
    return true if covers?(projection, scope, 'gerir')
    return false unless covers?(projection, scope, 'atender')
    return @conversation.assignee_id == @actor.id unless @target_id
    return true if @conversation.assignee_id.nil? && @target_id.to_s == @actor.id.to_s

    @conversation.assignee_id == @actor.id && covers?(projection, scope, 'transferir')
  end

  private

  def eligible_target?(scope)
    self.class.target_eligible?(account: @conversation.account, org_unit: scope&.org_unit, target_id: @target_id)
  end

  def covers?(projection, scope, permission)
    projection.granted_paths([permission]).any? { |path| scope.org_unit.path.start_with?(path) }
  end
end
