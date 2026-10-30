# Prepend em Api::V1::Accounts::InboxMembersController (instalado só pelo spike G0).
# Quem entra ou sai da inbox marcada muda quem vê as conversas dela: só o admin nominal altera membros.
module Connecta::Scope::InboxMembersHook
  private

  def fetch_inbox
    super
    return if request.get? || !Connecta::Scope::Projection.marked?(@inbox.id)

    allowed = Connecta::Scope::Projection.new(current_user).admin?
    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'inbox',
                                         access_path: "inbox_members_#{action_name}", decision: allowed ? 'allow' : 'deny')
    raise Connecta::Scope::Denied, :forbidden unless allowed
  end
end
