# Prepend em Api::V1::Accounts::Contacts::BaseController (instalado só pelo spike G0), base de labels, contact_inboxes, conversas e notas.
# Contato vinculado a inbox marcada: leitura só com conversa visível (404), escrita negada (403).
module Connecta::Scope::ContactSubresourceHook
  private

  def ensure_contact
    super
    Connecta::Scope::ContactVisibility.guard!(@contact, current_user, account: Current.account, read: request.get?)
  end
end
