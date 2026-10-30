# Prepend em Messages::MentionService (instalado só pelo spike G0). Em inbox marcada, menção a quem o Gate não deixa ler é descartada:
# sem participante, sem Mention, sem job e sem notificação. A mensagem continua salva.
module Connecta::Scope::MentionHook
  private

  def filter_mentioned_ids_by_inbox
    validated_ids = super
    conversation = message.conversation
    return validated_ids unless Connecta::Scope::Projection.marked?(conversation.inbox_id)

    validated_ids.select { |user_id| Connecta::Scope::Gate.new(User.find(user_id)).notifiable?(conversation) }
  end
end
