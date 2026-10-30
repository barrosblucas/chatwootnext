# Prepend em ConversationPolicy (instalado só pelo spike G0). Inboxes não marcadas seguem o show? nativo.
module Connecta::Scope::PolicyHook
  def show?
    return super unless Connecta::Scope::Projection.marked?(record.inbox_id)

    Connecta::Scope::Gate.new(user).read?(record, access_path: 'detail')
  end
end
