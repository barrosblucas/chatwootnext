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

  # Leitura de contato vinculado exige conversa visível (404). Escrita continua negada (403), exceto
  # a atualização que altera somente o nome (Correção 01, ver name_only_update?).
  def guard!(contact, user, account:, read:, name_only_update: false)
    return unless linked?(contact)
    raise Connecta::Scope::Denied, :not_found unless visible_scope(account, user).exists?(contact.id)
    return if read || name_only_update

    raise Connecta::Scope::Denied, :forbidden
  end

  # Correção 01: o escopo nega escrita em contato vinculado para preservar o conteúdo global; o nome
  # não é conteúdo do setor e pode ser corrigido por qualquer usuário da conta. O dashboard reenvia o
  # formulário inteiro, então cada campo é comparado com o valor persistido (branco equivale a nulo).
  # Qualquer diferença fora de `name` — inclusive avatar/avatar_url — mantém a negação nativa do guard.
  def name_only_update?(contact, attributes)
    changes = attributes.to_h.symbolize_keys
    return false unless changes.key?(:name)
    return false if changes[:avatar].present? || changes[:avatar_url].present?

    # avatar/avatar_url já negados acima quando presentes; chave vazia não altera nada no nativo.
    changes.except(:name, :avatar, :avatar_url).all? do |attribute, value|
      same_value?(contact.public_send(attribute), plain_value(value))
    end
  end

  def same_value?(current, incoming)
    return current == incoming if current.is_a?(Hash) || incoming.is_a?(Hash)

    normalize_blank(current) == normalize_blank(incoming)
  end

  def normalize_blank(value)
    value.is_a?(String) && value.strip.empty? ? nil : value
  end

  # Params aninhados chegam como ActionController::Parameters; compara com o jsonb persistido (chaves string).
  def plain_value(value)
    if defined?(ActionController::Parameters) && value.is_a?(ActionController::Parameters)
      value.to_unsafe_h
    elsif value.is_a?(Hash)
      value.transform_values { |entry| plain_value(entry) }
    elsif value.is_a?(Array)
      value.map { |entry| plain_value(entry) }
    else
      value
    end
  end
end
