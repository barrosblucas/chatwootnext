# Revalida push/e-mail pendente imediatamente antes da entrega.
module Connecta::Scope::NotificationDeliveryGuard
  private

  def connecta_scope_capture
    Connecta::Scope::DeliveryContext.for_notification(arguments.first)
  end

  def perform(notification)
    context = @connecta_scope_context
    conversation = Connecta::Scope::DeliveryContext.notification_conversation(notification)
    unless context
      return if conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)

      return super
    end
    return unless Connecta::Scope::DeliveryContext.notification_deliverable?(context, notification)

    Connecta::Scope::DeliveryContext.with(context, Connecta::Scope::DeliveryContext::MAILER) { super }
  end
end
