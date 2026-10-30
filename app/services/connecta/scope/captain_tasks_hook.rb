# Prepend em Api::V1::Accounts::Captain::TasksController (instalado só pelo spike G0).
# As tarefas de IA leem a conversa inteira e a enviam ao modelo: conversa de inbox marcada só com leitura autorizada, antes de qualquer chamada.
module Connecta::Scope::CaptainTasksHook
  private

  def connecta_scope_captain_guard!
    return if params[:conversation_display_id].blank?

    conversation = Current.account.conversations.find_by(display_id: params[:conversation_display_id])
    return unless conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)
    return if Connecta::Scope::Gate.new(current_user).read?(conversation, access_path: "captain_#{action_name}")

    raise Connecta::Scope::Denied, :not_found
  end
end
