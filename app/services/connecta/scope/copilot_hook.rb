# Prepend em Api::V1::Accounts::Captain::CopilotThreadsController e CopilotMessagesController (instalado só pelo spike G0).
# conversation_id externo de inbox marcada: só leitura autorizada pelo Gate; negado vira 404 (decisão 002), antes de
# persistência e enqueue. ID inexistente na conta também vira 404 (não revela se a conversa existe em outra conta).
module Connecta::Scope::CopilotHook
  private

  # Roda como before_action: o ResponseJob carrega o conversation_id e o contexto do modelo (CopilotChatHook) traz ID da
  # conversa e do contato, então negar depois da criação já seria vazamento. Negar aqui aborta antes de gravar thread.
  def connecta_scope_copilot_guard!
    conversation_id = params[:conversation_id]
    return if conversation_id.blank? || current_user.nil?

    conversation = Current.account.conversations.find_by(display_id: conversation_id)
    raise Connecta::Scope::Denied, :not_found if conversation.nil?
    return unless Connecta::Scope::Projection.marked?(conversation.inbox_id)
    return if Connecta::Scope::Gate.new(current_user).read?(conversation, access_path: 'copilot_conversation')

    raise Connecta::Scope::Denied, :not_found
  end
end
