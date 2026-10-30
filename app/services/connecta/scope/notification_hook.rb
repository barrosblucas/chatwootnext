# Prepend em NotificationBuilder (instalado só pelo spike G0). Em inbox marcada, notificação só para quem o Gate deixa ler como agente.
module Connecta::Scope::NotificationHook
  def perform
    conversation = primary_actor.is_a?(Conversation) ? primary_actor : primary_actor.try(:conversation)
    return super unless conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)
    return unless Connecta::Scope::Gate.new(user).notifiable?(conversation)

    super
  end
end
