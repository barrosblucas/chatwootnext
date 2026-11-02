class Connecta::Runtime::G0Adapter
  TABLES = {
    Connecta::Scope::ScopedInbox => 'connecta_scoped_inboxes',
    Connecta::Scope::OrgUnit => 'connecta_org_units',
    Connecta::Scope::UserGrant => 'connecta_user_grants',
    Connecta::Scope::UserAuthEpoch => 'connecta_user_auth_epochs',
    Connecta::Scope::AclSyncState => 'connecta_acl_sync_state',
    Connecta::Scope::ConversationScope => 'connecta_conversation_scopes',
    Connecta::Scope::AccessAudit => 'connecta_access_audits',
    Connecta::Transfer::TransferRecord => 'connecta_transfers',
    Connecta::Transfer::OutboundDispatchRecord => 'connecta_outbound_dispatches'
  }.freeze

  # Retorna true quando instala; false quando as tabelas ainda não existem (banco novo, antes da
  # migração). Nesse caso só registra aviso, para que `db:create`/`db:schema:load`/`db:migrate`
  # rodem. Outras falhas continuam estourando.
  def self.install!
    missing_tables = TABLES.values.reject { |table| ActiveRecord::Base.connection.data_source_exists?(table) }
    if missing_tables.any?
      Rails.logger.warn("Connecta runtime not installed: tables missing (#{missing_tables.join(', ')}); run the additive Connecta migration first")
      return false
    end

    TABLES.each { |model, table| model.table_name = table }
    patch_projection
    patch_conversation_query
    patch_outbound_claim
    Connecta::Scope::Gate.prepend(GateContainmentHook) unless Connecta::Scope::Gate <= GateContainmentHook
    true
  end

  def self.patch_projection
    Connecta::Scope::Projection.prepend(ProjectionTablesHook) unless Connecta::Scope::Projection <= ProjectionTablesHook
  end

  def self.patch_conversation_query
    return if Connecta::Scope::ConversationQuery <= ConversationQueryTablesHook

    Connecta::Scope::ConversationQuery.prepend(ConversationQueryTablesHook)
  end

  def self.patch_outbound_claim
    model = Connecta::Transfer::OutboundDispatch
    model.send(:remove_const, :CLAIM_SQL) if model.const_defined?(:CLAIM_SQL, false)
    model.const_set(:CLAIM_SQL, <<~SQL.squish.freeze)
      UPDATE connecta_outbound_dispatches AS d
      SET state = CASE WHEN EXISTS (
            SELECT 1 FROM connecta_conversation_scopes AS s
            JOIN connecta_scoped_inboxes AS i ON i.inbox_id = s.inbox_id
            JOIN messages AS m ON m.id = d.message_id
            WHERE s.conversation_id = d.conversation_id
              AND i.enforcement = 'enforce' AND i.maintenance = false
              AND (s.state = 'active' OR (s.state = 'reception' AND m.sender_type = 'User' AND m.sender_id IN (?)))
          ) THEN 'dispatching' ELSE 'parked' END,
          attempted_at = now(), updated_at = now()
      WHERE d.message_id = ? AND d.state = 'queued'
      RETURNING d.state
    SQL
  end

  module ProjectionTablesHook
    def fresh?
      Connecta::Scope::AclSyncState.exists?(['last_heartbeat_at > ?', Connecta::Scope::Projection.heartbeat_ttl.ago])
    rescue ArgumentError
      false
    end

    def granted_paths(permissions)
      Connecta::Scope::UserGrant.joins(:org_unit)
                                .where(user_id: user.id, permission: permissions, connecta_org_units: { enabled: true })
                                .pluck('connecta_org_units.path')
    end
  end

  module ConversationQueryTablesHook
    private

    def visible_conversation_ids
      Connecta::Scope::ConversationScope.joins(:org_unit)
                                        .where(state: Connecta::Scope::ConversationScope::READ_STATES, inbox_id: enforced_inbox_ids)
                                        .where(connecta_org_units: { enabled: true })
                                        .where('connecta_org_units.path LIKE ANY (ARRAY[?]::text[])', read_path_patterns)
                                        .select(:conversation_id)
    end
  end

  module GateContainmentHook
    private

    # T3.9: espelha o Gate quando os modelos estão retargetados às tabelas de
    # produto. admin_only e maintenance mantêm a inbox marcada; o Gate decide
    # a negação (admin_only nega não-admin, maintenance bloqueia a escrita).
    def enforced?(inbox_id)
      Connecta::Scope::ScopedInbox.exists?(inbox_id: inbox_id)
    end

    def state_allows?(scope, action)
      return false if action == :write && Connecta::Scope::ScopedInbox.where(inbox_id: scope.inbox_id).exists?(
        ['maintenance = ? OR enforcement = ?', true, 'maintenance']
      )

      super
    end
  end
end
