# Última verificação antes do envio SMTP para e-mails de conversa marcada.
module Connecta::Scope::MailDeliveryGuard
  private

  def connecta_scope_mail_guard!
    return unless @conversation.is_a?(Conversation) && Connecta::Scope::Projection.marked?(@conversation.inbox_id)

    throw :abort unless connecta_scope_notification_valid?
  end

  def connecta_scope_notification_valid?
    context = Connecta::Scope::DeliveryContext.take(Connecta::Scope::DeliveryContext::MAILER)
    notification = context.is_a?(Hash) ? Notification.find_by(id: context['notification_id']) : nil
    return false unless notification && notification.user_id == @agent&.id && notification.primary_actor_id == @conversation.id
    return false unless Array(message.to) == [notification.user.email]

    Connecta::Scope::DeliveryContext.notification_deliverable?(context, notification)
  end
end
