class Connecta::Scope::AssignmentPolicy
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
    target = @conversation.account.users.find_by(id: @target_id)
    return false unless target

    projection = Connecta::Scope::Projection.new(target)
    projection.usable? && covers?(projection, scope, 'atender')
  end

  def covers?(projection, scope, permission)
    projection.granted_paths([permission]).any? { |path| scope.org_unit.path.start_with?(path) }
  end
end
