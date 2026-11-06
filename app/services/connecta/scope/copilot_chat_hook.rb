# Prepend em Captain::Copilot::ChatService (instalado só pelo spike G0).
# O histórico e as ferramentas que leem conversa respeitam o Gate: negado vira vazio (o Copilot devolve "não encontrado",
# sem ID de conversa ou contato). Conversa em inbox não marcada segue nativa.
# O ResponseJob monta o contexto com o conversation_id vindo do create (já barrado no HTTP); se o job for enfileirado
# por outro caminho, o Gate aqui impede que ID de conversa e contato alheios cheguem ao modelo.
module Connecta::Scope::CopilotChatHook
  private

  def current_viewing_history
    return [] if connecta_scope_copilot_denied?(@conversation_id, 'copilot_context')

    super
  end

  def connecta_scope_copilot_denied?(conversation_id, access_path)
    return false if conversation_id.blank?

    conversation = @account.conversations.find_by(display_id: conversation_id)
    return false unless conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)
    return true if @user.nil?

    !Connecta::Scope::Gate.new(@user).read?(conversation, access_path: access_path)
  end
end
