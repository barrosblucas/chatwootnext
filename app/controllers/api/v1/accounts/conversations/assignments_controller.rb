class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  # assigns agent/team to a conversation
  def create
    if params.key?(:assignee_id) || agent_bot_assignment?
      set_agent
    elsif params.key?(:team_id)
      set_team
    else
      render json: nil
    end
  end

  private

  def set_agent
    resource = nil
    @conversation.with_lock do
      dest_id = params[:connecta_org_unit_id].presence
      if dest_id && Connecta::Scope::Projection.marked?(@conversation.inbox_id)
        resource = connecta_assign_with_unit(dest_id.to_s)
        return if performed?
      else
        if Connecta::Scope::Projection.marked?(@conversation.inbox_id) &&
           !Connecta::Scope::AssignmentPolicy.new(conversation: @conversation, actor: Current.user,
                                                  target_id: params[:assignee_id], target_type: params[:assignee_type]).allowed?
          return head :forbidden
        end

        resource = Conversations::AssignmentService.new(
          conversation: @conversation,
          assignee_id: params[:assignee_id],
          assignee_type: params[:assignee_type]
        ).perform
      end
    end

    render_agent(resource)
  end

  # Cross-unit assign (gestor/admin): the conversation moves to the destination
  # unit through the same TransferTransaction the transfer endpoint uses (scope
  # state, audit and whatsapp-platform propagation identical to a sector
  # transfer), then the target is assigned on the destination conversation.
  # Same unit or unresolvable destination falls back to the current behaviour;
  # rule failures answer head :forbidden like other assignment denials.
  def connecta_assign_with_unit(dest_id)
    scope = Connecta::Scope::ConversationScope.includes(:org_unit).find_by(conversation_id: @conversation.id)
    return head :forbidden if scope.nil? || !scope.org_unit&.enabled?

    destination = connecta_destination_unit(dest_id)
    # Same message/status the transfer path answers for an unknown destination
    # (TransferTransaction.build_local_transaction): the move cannot start.
    if destination.nil?
      render json: { error: 'Destination unit is not synchronized' }, status: :unprocessable_entity
      return nil
    end
    return connecta_assign_same_unit!(scope) if destination.id.to_s == scope.org_unit_id.to_s

    return head :forbidden unless connecta_cross_unit_actor_allowed?(scope.org_unit, destination)
    return head :forbidden unless Connecta::Scope::AssignmentPolicy.target_eligible?(
      account: Current.account, org_unit: destination, target_id: params[:assignee_id]
    )

    transfer = connecta_move_unit!(scope.org_unit, destination)
    return nil if transfer.nil?

    destination_conversation = Conversation.find(
      Connecta::Transfer::TransferRecord.find(transfer[:transfer_id]).destination_conversation_id
    )
    Conversations::AssignmentService.new(
      conversation: destination_conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform
  end

  def connecta_assign_same_unit!(scope)
    unless Connecta::Scope::AssignmentPolicy.new(conversation: @conversation, actor: Current.user,
                                                 target_id: params[:assignee_id],
                                                 target_type: params[:assignee_type]).allowed?
      head :forbidden
      return nil
    end

    Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform
  end

  # Native admin, or gerir covering both source and destination units.
  def connecta_cross_unit_actor_allowed?(source_unit, destination_unit)
    return true if Connecta::Scope::NativeAdmin.authorized_for?(Current.user, @conversation)

    projection = Connecta::Scope::Projection.new(Current.user)
    return false unless projection.usable?

    gerir_paths = projection.granted_paths(['gerir'])
    [source_unit, destination_unit].all? do |unit|
      gerir_paths.any? { |path| unit.path.start_with?(path) }
    end
  end

  # The unit move itself reuses TransferTransaction (TransferPolicy authorize +
  # local transaction + platform prepare/commit + TransferCommitJob), so audit,
  # scope state and propagation match a normal sector transfer. The summary is
  # system-generated assignment metadata (no case content is fabricated).
  def connecta_move_unit!(source_unit, destination)
    Connecta::Runtime::TransferTransaction.new(
      account_id: Current.account.id,
      conversation: @conversation,
      actor: Current.user,
      destination_org_unit_id: destination.id,
      summary: connecta_assign_summary(source_unit, destination)
    ).call
  rescue Connecta::Runtime::TransferTransaction::Error => e
    render json: { error: e.message }, status: e.status
    nil
  end

  # Malformed ids (e.g. non-UUID on a uuid column) fail closed as an
  # unknown destination instead of raising through the driver.
  def connecta_destination_unit(dest_id)
    Connecta::Scope::OrgUnit.find_by(id: dest_id, enabled: true)
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def connecta_assign_summary(source_unit, destination)
    target = Current.account.users.find_by(id: params[:assignee_id])
    {
      subject: 'Mudança de setor por atribuição',
      completed: "Conversa movida de #{source_unit.name} para #{destination.name} por #{Current.user.name}.",
      next_action: "Seguir o atendimento em #{destination.name} (responsável: #{target&.name})."
    }
  end

  def render_agent(resource)
    case resource
    when User
      render partial: 'api/v1/models/agent', formats: [:json], locals: { resource: resource }
    when AgentBot
      render partial: 'api/v1/models/agent_bot_slim', formats: [:json], locals: { resource: resource }
    else
      render json: nil
    end
  end

  def set_team
    team_id = params[:team_id].to_i
    @team = team_id.positive? ? Current.account.teams.find(team_id) : nil
    @conversation.with_lock do
      @conversation.update!(team: @team)
    end
    render json: @team
  end

  def agent_bot_assignment?
    params[:assignee_type].to_s == 'AgentBot'
  end
end
