# Prepend em Contacts::FilterService (instalado só pelo spike G0). Lista e contagem do filtro saem só com contatos visíveis.
module Connecta::Scope::ContactFilterServiceHook
  def perform
    result = super
    contacts = result[:contacts].where(id: Connecta::Scope::ContactVisibility.visible_scope(@account, @user).select(:id))
    { contacts: contacts, count: contacts.count }
  end
end
