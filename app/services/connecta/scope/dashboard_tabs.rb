# Dashboard opt-in tabs (Correcao 02): explicit namespaced contract for the
# Connecta queue tabs. Runs only when `connecta_dashboard=true`; every other
# caller keeps the native path untouched.
#
# All tabs share the authorized base (ConversationQuery already ran inside the
# finder) and the same relation feeds list and meta counts, so totals always
# match the rows. Sector selection narrows by verified org-unit path prefix;
# grants are never derived from inbox or team. Todos/Bot are account-admin
# only; denied or invalid selections fail closed to an empty relation (same
# empty shape, so callers cannot probe which rule fired).
class Connecta::Scope::DashboardTabs
  OPT_IN_VALUE = 'true'.freeze
  TABS = %w[minhas aguardando todos bot].freeze
  # Human attendance for Todos: triaged and stable. `active` covers the open
  # queue; `closed` covers operator-resolved history (the resolution lifecycle
  # keeps sector/protocol on close). Transient states (reception without
  # protocol, pending_activation, transferring, activation_stuck) and
  # scope-less legacy rows belong to neither queue.
  # Ambiguity note: `transferring` rows carry a protocol but are in flight to
  # another sector; they are excluded from both Todos and Aguardando.
  HUMAN_STATES = %w[active closed].freeze

  class << self
    def opt_in?(params)
      fetch(params, :connecta_dashboard) == OPT_IN_VALUE
    end

    # Validated tab predicate over the authorized base relation. Invalid
    # tab/unit, denied sector or denied admin tab all fail closed to none.
    def apply(relation, user:, account:, params:)
      tab = validated_tab(params)
      return relation.none if tab.nil?

      marked_ids = Connecta::Scope::Projection.marked_inbox_ids
      unit = selected_unit(params)
      return relation.none if unit == :invalid
      return relation.none if unit && !sector_allowed?(user, account, unit)
      return relation.none unless sectors_granted?(user, account)

      relation = narrow_to_unit(relation, marked_ids, unit) if unit
      apply_tab(relation, tab, user: user, account: account, marked_ids: marked_ids)
    end

    # Read-only catalog for the dashboard sector filter: the enabled units
    # the actor may read under exactly the same account-scoped rule as
    # choosing a sector (`sector_allowed?`). Native account admins see every
    # enabled unit; anyone else needs a usable projection plus a read-grant
    # prefix (the grant covers the sector plus its descendants, like the
    # per-row Gate). Missing or unusable projections fail closed to none.
    # Single query with no N+1: one fetch of the enabled units, then the same
    # in-memory prefix test as the selected-sector check.
    def authorized_units(user:, account:)
      return Connecta::Scope::OrgUnit.where(enabled: true).order(:name) if Connecta::Scope::NativeAdmin.administrator?(user, account)

      projection = Connecta::Scope::Projection.new(user)
      return Connecta::Scope::OrgUnit.none unless projection.usable?

      paths = projection.granted_paths(Connecta::Scope::Gate::READ_PERMISSIONS)
      return Connecta::Scope::OrgUnit.none if paths.empty?

      Connecta::Scope::OrgUnit.where(enabled: true).order(:name).select { |unit| covers?(unit.path, paths) }
    end

    private

    def apply_tab(relation, tab, user:, account:, marked_ids:)
      case tab
      when 'minhas'
        relation.assigned_to(user)
      when 'aguardando'
        Connecta::Scope::BotEligibility.human_only(relation, marked_ids)
      when 'bot'
        bot_tab(relation, user: user, account: account)
      when 'todos'
        todos_tab(relation, marked_ids, user: user, account: account)
      end
    end

    # Aguardando agrega os setores autorizados: sem nenhum setor legivel o
    # ator nao ve nenhuma aba (falha fechado vazio, sem vazar totais).
    # Admin nativo mantem full same-account (mesma regra de `sector_allowed?`).
    def sectors_granted?(user, account)
      return true if Connecta::Scope::NativeAdmin.administrator?(user, account)

      projection = Connecta::Scope::Projection.new(user)
      return false unless projection.usable?

      projection.granted_paths(Connecta::Scope::Gate::READ_PERMISSIONS).any?
    end

    # Bot canonico do servidor: so admin, com confirmacao da plataforma
    # (falha fechada com 503 via BotEligibility::Unavailable, nunca parcial).
    def bot_tab(relation, user:, account:)
      return relation.none unless Connecta::Scope::NativeAdmin.administrator?(user, account)
      raise_unless_bot_available!

      Connecta::Scope::BotEligibility.new(relation).perform
    end

    def raise_unless_bot_available?
      return if Connecta::Scope::BotEligibility.available?

      raise Connecta::Scope::BotEligibility::Unavailable, Connecta::Scope::BotEligibility::UNAVAILABLE_CODE
    end

    # Todos: atendimento humano dos setores autorizados, nunca linhas Bot;
    # so admin (nao-admin nega sem vazar totais de badge).
    def todos_tab(relation, marked_ids, user:, account:)
      return relation.none unless Connecta::Scope::NativeAdmin.administrator?(user, account)

      human_attendances(relation, marked_ids)
    end

    # Todos predicate: human attendances of the scoped sectors, never Bot
    # rows. Marked inboxes keep rows with a triaged protocol on an enabled
    # unit in a stable state; unmarked inboxes pass through intact (legacy).
    def human_attendances(relation, marked_ids)
      scope_table = Conversation.connection.quote_table_name(Connecta::Scope::ConversationScope.table_name)
      unit_table = Conversation.connection.quote_table_name(Connecta::Scope::OrgUnit.table_name)
      states = HUMAN_STATES.map { |state| "'#{state}'" }.join(', ')
      relation.where.not(inbox_id: marked_ids).or(
        relation.where(
          "EXISTS (SELECT 1 FROM #{scope_table} human_scope " \
          "INNER JOIN #{unit_table} human_unit " \
          'ON human_unit.id = human_scope.org_unit_id AND human_unit.enabled = TRUE ' \
          'WHERE human_scope.conversation_id = conversations.id ' \
          'AND human_scope.inbox_id = conversations.inbox_id ' \
          "AND human_scope.state IN (#{states}) " \
          "AND NULLIF(BTRIM(human_scope.case_protocol), '') IS NOT NULL)"
        )
      )
    end

    # Sector narrowing by verified path prefix (the sector plus descendants).
    # Unmarked inboxes stay intact so legacy controls keep native results.
    def narrow_to_unit(relation, marked_ids, unit)
      scope_table = Conversation.connection.quote_table_name(Connecta::Scope::ConversationScope.table_name)
      unit_table = Conversation.connection.quote_table_name(Connecta::Scope::OrgUnit.table_name)
      relation.where.not(inbox_id: marked_ids).or(
        relation.where(
          "EXISTS (SELECT 1 FROM #{scope_table} narrow_scope " \
          "INNER JOIN #{unit_table} narrow_unit " \
          'ON narrow_unit.id = narrow_scope.org_unit_id ' \
          'WHERE narrow_scope.conversation_id = conversations.id ' \
          'AND narrow_scope.inbox_id = conversations.inbox_id ' \
          'AND narrow_unit.path LIKE ?)', "#{unit.path}%"
        )
      )
    end

    # Same rule the Gate enforces per row (prefix grant over the sector path,
    # usable projection), checked here for the selected sector itself. Native
    # account admins keep their established same-account semantics.
    def sector_allowed?(user, account, unit)
      return true if Connecta::Scope::NativeAdmin.administrator?(user, account)

      projection = Connecta::Scope::Projection.new(user)
      return false unless projection.usable?

      covers?(unit.path, projection.granted_paths(Connecta::Scope::Gate::READ_PERMISSIONS))
    end

    # Shared prefix grant test (sector plus descendants): the unit path starts
    # with a granted path, the same direction the per-row Gate enforces.
    def covers?(unit_path, granted_paths)
      granted_paths.any? { |path| unit_path.start_with?(path) }
    end

    def validated_tab(params)
      tab = fetch(params, :connecta_tab)
      TABS.include?(tab) ? tab : nil
    end

    # nil = absent (aggregate authorized sectors); :invalid = fail closed
    # (missing, disabled, or malformed selection is indistinguishable from
    # denied, so selections cannot probe for sectors).
    def selected_unit(params)
      raw = fetch(params, :connecta_org_unit_id)
      return nil if raw.nil? || raw.to_s.strip.empty?

      id = Integer(raw.to_s, 10)
      return :invalid unless id.positive?

      unit = Connecta::Scope::OrgUnit.find_by(id: id)
      return :invalid if unit.nil? || !unit.enabled?

      unit
    rescue ArgumentError
      :invalid
    end

    def fetch(params, key)
      params[key].nil? ? params[key.to_s] : params[key]
    end
  end
end
