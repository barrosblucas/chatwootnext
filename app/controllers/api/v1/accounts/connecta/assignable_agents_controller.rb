class Api::V1::Accounts::Connecta::AssignableAgentsController < Api::V1::Accounts::BaseController
  # Department-scoped assignable agents. Contract (frozen for the frontend):
  # GET /api/v1/accounts/:account_id/connecta/assignable_agents?conversation_ids[]=DISPLAY_ID...
  # 200: { grouped: bool, conversation_org_unit_id: uuid|null,
  #        groups: [ { org_unit_id: uuid|null, org_unit_name: string|null, agents: [<agent JSON>] } ] }
  # `grouped` = groups.length > 1. The per-agent JSON is the same partial the
  # native assignable_agents endpoint renders (api/v1/models/agent).
  def index
    display_ids = Array(params[:conversation_ids]).reject(&:blank?).map(&:to_s).uniq
    return render json: { error: I18n.t('errors.conversations.connecta_assignable_agents.conversation_ids_required') },
                  status: :unprocessable_entity if display_ids.empty?

    conversations = display_ids.map { |display_id| find_conversation!(display_id) }
    scoped = load_scopes(conversations)

    if conversations.size == 1
      render_single(conversations.first, scoped[conversations.first.id])
    else
      render_bulk(conversations, scoped)
    end
  rescue Connecta::Scope::Denied => e
    render json: { error: e.message }, status: e.status
  end

  private

  def find_conversation!(display_id)
    Current.account.conversations.find_by!(display_id: display_id)
  end

  def load_scopes(conversations)
    ids = conversations.map(&:id)
    Connecta::Scope::ConversationScope.includes(:org_unit).where(conversation_id: ids).index_by(&:conversation_id)
  end

  def marked_inbox?(conversation)
    Connecta::Scope::Projection.marked?(conversation.inbox_id)
  end

  # Read gate per conversation: scoped => Connecta Gate (denied reads 404 like
  # the conversation endpoints); unscoped => native Pundit show?.
  def authorize_read!(conversation)
    if marked_inbox?(conversation)
      gate = Connecta::Scope::Gate.new(Current.user)
      raise Connecta::Scope::Denied, :not_found unless gate.read?(conversation, access_path: 'connecta_assignable_agents')
    else
      authorize conversation, :show?
    end
  end

  def render_single(conversation, scope)
    authorize_read!(conversation)
    return render_unscoped(conversation) unless marked_inbox?(conversation)
    raise Connecta::Scope::Denied, :not_found if scope.nil?

    units = visible_units(conversation, scope)
    ids_by_unit = Connecta::Scope::AssignmentPolicy.eligible_target_ids_by_unit(account: Current.account, org_units: units)
    agents_by_unit = load_agents(ids_by_unit)
    groups = units.filter_map do |unit|
      next if unit.id != scope.org_unit_id && agents_by_unit[unit.id].empty?

      group_for(unit, agents_by_unit[unit.id])
    end
    groups = groups.sort_by { |group| I18n.transliterate(group[:org_unit_name].to_s).downcase }

    @grouped = groups.size > 1
    @conversation_org_unit_id = scope.org_unit_id
    @groups = groups
    render template: 'api/v1/accounts/connecta/assignable_agents/index'
  end

  def render_unscoped(conversation)
    agents = native_assignable(conversation.inbox_id)
    @grouped = false
    @conversation_org_unit_id = nil
    @groups = [{ org_unit_id: nil, org_unit_name: nil, agents: agents }]
    render template: 'api/v1/accounts/connecta/assignable_agents/index'
  end

  def render_bulk(conversations, scoped)
    conversations.each { |conversation| authorize_read!(conversation) }
    sets = conversations.map do |conversation|
      scope = scoped[conversation.id]
      if scope&.org_unit
        ids = Connecta::Scope::AssignmentPolicy.eligible_target_ids_by_unit(account: Current.account, org_units: [scope.org_unit])
        ids[scope.org_unit.id].to_set
      else
        native_assignable_set(conversation.inbox_id)
      end
    end
    shared = (sets.reduce(:&) || Set.new) - reception_sender_ids
    @grouped = false
    @conversation_org_unit_id = nil
    @groups = [{ org_unit_id: nil, org_unit_name: nil, agents: load_sorted_agents(shared) }]
    render template: 'api/v1/accounts/connecta/assignable_agents/index'
  end

  # Base group = the conversation unit (always present); extra groups = every
  # enabled unit the actor may pull from: all units with eligible agents for a
  # native admin, gerir-covered units for a manager. A plain atendente keeps
  # only the conversation unit.
  def visible_units(conversation, scope)
    base = scope.org_unit
    extra = []
    if Connecta::Scope::NativeAdmin.authorized_for?(Current.user, conversation)
      extra = Connecta::Scope::OrgUnit.where(enabled: true).to_a - [base]
    else
      projection = Connecta::Scope::Projection.new(Current.user)
      if projection.usable?
        gerir_paths = projection.granted_paths(['gerir'])
        unless gerir_paths.empty?
          extra = Connecta::Scope::OrgUnit.where(enabled: true).to_a.select do |unit|
            unit.id != base.id && gerir_paths.any? { |path| unit.path.start_with?(path) }
          end
        end
      end
    end
    [base] + extra
  end

  def group_for(unit, agents)
    { org_unit_id: unit.id, org_unit_name: unit.name, agents: sort_agents(agents) }
  end

  def load_agents(ids_by_unit)
    all_ids = ids_by_unit.values.flatten.uniq - reception_sender_ids.to_a
    users = Current.account.users.where(id: all_ids).index_by(&:id)
    ids_by_unit.transform_values { |ids| sort_agents(ids.filter_map { |id| users[id] }) }
  end

  def native_assignable(inbox_id)
    load_sorted_agents(native_assignable_set(inbox_id))
  end

  # Native list for an unscoped inbox: inbox members + administrators, minus
  # reception senders. Mirrors AssignableAgentsController#index.
  def native_assignable_set(inbox_id)
    member_ids = Current.account.inboxes.find(inbox_id).members.pluck(:user_id)
    (member_ids + Current.account.administrators.ids).map(&:to_i).to_set - reception_sender_ids
  end

  def load_sorted_agents(id_set)
    ids = id_set.uniq - reception_sender_ids.to_a
    sort_agents(Current.account.users.where(id: ids).to_a)
  end

  def reception_sender_ids
    @reception_sender_ids ||= Connecta::Runtime::Feature.reception_sender_user_ids.map(&:to_i).to_set
  end

  def sort_agents(agents)
    agents.sort_by { |agent| I18n.transliterate(agent.name.to_s).downcase }
  end
end
