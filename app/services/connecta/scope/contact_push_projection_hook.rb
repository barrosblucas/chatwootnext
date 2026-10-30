# Projeta o DTO do contato sem alterar getters ou os atributos persistidos.
module Connecta::Scope::ContactPushProjectionHook
  def push_event_data
    data = super
    if Connecta::Scope::ContactDataProjection.restricted_contact?(self, Current.user)
      Connecta::Scope::ContactDataProjection.redact_contact(data)
    else
      data
    end
  end
end
