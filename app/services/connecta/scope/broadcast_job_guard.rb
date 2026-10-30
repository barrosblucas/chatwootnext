# Revalida destinatários e projeta o payload recarregado pelo job nativo.
module Connecta::Scope::BroadcastJobGuard
  private

  def connecta_scope_capture
    Connecta::Scope::DeliveryContext.take(self.class.name)
  end

  def perform(members, event_name, data)
    context = @connecta_scope_context
    allowed = Connecta::Scope::DeliveryCheck.allowed_tokens(context, members, event_name, data)
    return if allowed.blank?

    super(allowed, event_name, data)
  end

  def prepare_broadcast_data(event_name, data)
    prepared = super
    context = @connecta_scope_context
    Connecta::Scope::ContactDataProjection.socket_payload(
      prepared, force_contact: context.is_a?(Hash) && context['kind'] == 'contact_deleted'
    )
  end
end
