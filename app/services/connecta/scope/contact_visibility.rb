# Contato com vínculo em inbox marcada só é visível a quem vê alguma conversa dele nessa inbox (spike G0).
# Contato sem vínculo com inbox marcada segue o comportamento nativo. Admin nominal não vê contato vinculado (sem conteúdo por lista).
module Connecta::Scope::ContactVisibility
  module_function

  def linked?(contact)
    ::ContactInbox.exists?(contact_id: contact.id, inbox_id: Connecta::Scope::Projection.marked_inbox_ids)
  end

  def linked_ids
    ::ContactInbox.where(inbox_id: Connecta::Scope::Projection.marked_inbox_ids).select(:contact_id)
  end

  def visible_scope(account, user)
    marked_conversations = account.conversations.where(inbox_id: Connecta::Scope::Projection.marked_inbox_ids)
    visible_contact_ids = Connecta::Scope::ConversationQuery.new(marked_conversations, user).perform.select(:contact_id)

    account.contacts.where.not(id: linked_ids).or(account.contacts.where(id: visible_contact_ids))
  end

  # Leitura de contato vinculado exige conversa visível (404). Escrita nunca é liberada aqui (403).
  def guard!(contact, user, account:, read:)
    return unless linked?(contact)
    raise Connecta::Scope::Denied, :not_found unless visible_scope(account, user).exists?(contact.id)
    raise Connecta::Scope::Denied, :forbidden unless read
  end
end
