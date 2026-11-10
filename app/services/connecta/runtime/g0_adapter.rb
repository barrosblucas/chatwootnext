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

  # Sem efeito desde a Fase 2: `OutboundDispatch.claim_sql` monta o SQL com as
  # tabelas vivas dos modelos (+ exceção da pesquisa CSAT em escopo `closed`),
  # então não há mais constante para remapear. Mantido como no-op para não
  # quebrar chamadores.
  def self.patch_outbound_claim
    nil
  end

  module ProjectionTablesHook
    def fresh?
      Connecta::Scope::AclSyncState.exists?(['last_heartbeat_at > ?', Connecta::Scope::Projection.heartbeat_ttl.ago])
    rescue ArgumentError
      false
    end

    def granted_paths(permissions)
      @granted_paths ||= {}
      key = Array(permissions).map(&:to_s).sort.freeze
      @granted_paths[key] ||= Connecta::Scope::UserGrant.joins(:org_unit)
                                                        .where(user_id: user.id, permission: permissions,
                                                               connecta_org_units: { enabled: true })
                                                        .pluck('connecta_org_units.path')
                                                        .freeze
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
