# Em conversa marcada, o guard de push/email mantém o envio dentro do mesmo job.
module Connecta::Scope::EmailDeliveryHook
  private

  def send_notification_email
    conversation = notification.primary_actor.is_a?(Conversation) ? notification.primary_actor : notification.primary_actor.try(:conversation)
    return super unless conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)

    AgentNotifications::ConversationNotificationsMailer.with(account: notification.account).public_send(
      notification.notification_type.to_s, notification.primary_actor, notification.user, notification.secondary_actor
    ).deliver_now
  end
end
