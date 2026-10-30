class Api::V1::Accounts::Conversations::ConnectaScopesController < Api::V1::Accounts::Conversations::BaseController
  def show
    scope = Connecta::Scope::ConversationScope.find_by(conversation_id: @conversation.id)
    return head :not_found unless scope

    gate = Connecta::Scope::Gate.new(current_user)
    return head :not_found unless gate.read?(@conversation, access_path: 'connecta_scope')

    dispatch = Connecta::OutboundDispatch.where(conversation_id: @conversation.id).order(:id).last
    can_transfer = can_transfer?(scope)
    render json: {
      state: scope.state, case_version: scope.case_version,
      dispatch_state: dispatch&.state, case_protocol: scope.case_protocol, can_transfer: can_transfer
    }
  end

  private

  def can_transfer?(scope)
    return true if Connecta::Scope::NativeAdmin.authorized_for?(current_user, @conversation)

    projection = Connecta::Scope::Projection.new(current_user)
    unit_path = scope.org_unit.path
    projection.verified? && projection.fresh? &&
      projection.granted_paths(['transferir']).any? { |path| unit_path.start_with?(path) }
  end
end
