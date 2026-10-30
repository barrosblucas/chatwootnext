# Prepend nas ferramentas Copilot que leem conversa e contato (instalado só pelo spike G0).
# Leitura negada pelo Gate vira "não encontrado" (a ferramenta devolve texto, não HTTP): sem ID, sem contato, sem conteúdo.
# SearchConversationsService já passa pelo FinderHook via PermissionFilterService (instalado no spike); as demais
# ferramentas fazem lookup direto e precisam do guard aqui. Sem usuário, negar é fail-closed.
module Connecta::Scope::CopilotToolHook
  def execute(*, **)
    scoped = connecta_scope_copilot_search_contacts(*, **)
    return scoped unless scoped.nil?

    denied_text = connecta_scope_copilot_tool_guard_text(*, **)
    return denied_text if denied_text

    scoped_contact = connecta_scope_copilot_get_contact(*, **)
    return scoped_contact unless scoped_contact.nil?

    super
  end

  private

  # Filtro individual RF1 antes de formatar: escopo visivel do proprio ator; fatiar piora clareza.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def connecta_scope_copilot_search_contacts(*, **kwargs)
    short = self.class.name
    return nil unless short == 'Captain::Tools::Copilot::SearchContactsService' || short == 'search_contacts'
    return 'Contact not found' if @user.nil?

    # Nativa: enterprise/app/services/captain/tools/copilot/search_contacts_service.rb:12.
    # Filtros reproduzidos 1:1 da nativa e aplicados SOBRE o escopo visivel do proprio ator
    # (ContactVisibility): nenhum resultado alheio chega ao LlmFormatter/resposta.
    account = @assistant.account
    email = kwargs[:email] || kwargs['email']
    phone_number = kwargs[:phone_number] || kwargs['phone_number']
    name = kwargs[:name] || kwargs['name']

    scope = Connecta::Scope::ContactVisibility.visible_scope(account, @user)
    scope = scope.where(email: email) if email.present?
    scope = scope.where(phone_number: phone_number) if phone_number.present?
    scope = scope.where('LOWER(contacts.name) ILIKE ?', "%#{name.to_s.downcase}%") if name.present?

    return 'No contacts found' unless scope.exists?

    scoped = scope.limit(100)

    <<~RESPONSE
      #{scoped.map { |contact| Connecta::Scope::ContactDataProjection.llm_text(contact, @user) }.join("\n---\n")}
    RESPONSE
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Get por id visivel: guard de conta/visibilidade acima decide negar; aqui so
  # formata pela mesma API do search, com o proprio @user (nunca Current.user).
  # Guards de conversa/search inalterados; sem regex sobre texto com segredo.
  # rubocop:disable Metrics/CyclomaticComplexity
  def connecta_scope_copilot_get_contact(*args, **kwargs)
    short = self.class.name
    return nil unless short == 'Captain::Tools::Copilot::GetContactService' || short == 'get_contact'

    contact_id = kwargs[:contact_id] || kwargs['contact_id'] || args.first
    return nil if contact_id.blank?
    return 'Contact not found' if @user.nil?

    account = @assistant.account
    visible = Connecta::Scope::ContactVisibility.visible_scope(account, @user)
    contact = visible.find_by(id: contact_id)
    return nil if contact.nil?

    Connecta::Scope::ContactDataProjection.llm_text(contact, @user)
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def connecta_scope_copilot_tool_guard_text(*, **)
    # As ferramentas nativas sobrescrevem `def self.name` ('get_conversation', 'get_contact',
    # 'search_contacts'): `self.class.name` devolve o nome curto, nunca o FQCN. Casar os dois,
    # senão o guard nunca roda e o lookup direto vaza alvo alheio (falhas 306/320/334).
    case self.class.name
    when 'Captain::Tools::Copilot::GetConversationService', 'get_conversation'
      return 'Conversation not found' if connecta_scope_copilot_conversation_denied?(*, **)
    when 'Captain::Tools::Copilot::GetContactService', 'get_contact'
      return 'Contact not found' if connecta_scope_copilot_contact_denied?(*, **)
    end

    nil
  end

  def connecta_scope_copilot_conversation_denied?(*args, **kwargs)
    conversation_id = kwargs[:conversation_id] || kwargs['conversation_id'] || args.first
    return false if conversation_id.blank?
    return true if @user.nil?

    account = @assistant.account
    scope = Connecta::Scope::ConversationQuery.new(account.conversations, @user).perform
    !scope.exists?(display_id: conversation_id)
  end

  # Guard único de contato: extrair artificialmente pioraria a clareza do filtro por setor.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def connecta_scope_copilot_contact_denied?(*args, **kwargs)
    contact_id = kwargs[:contact_id] || kwargs['contact_id'] || args.first
    email = kwargs[:email] || kwargs['email']
    phone_number = kwargs[:phone_number] || kwargs['phone_number']
    name = kwargs[:name] || kwargs['name']
    return false if contact_id.blank? && email.blank? && phone_number.blank? && name.blank?
    return true if @user.nil?

    account = @assistant.account
    visible = Connecta::Scope::ContactVisibility.visible_scope(account, @user)
    if contact_id.present?
      return true unless visible.exists?(id: contact_id)
    else
      candidates = account.contacts
      candidates = candidates.where(email: email) if email.present?
      candidates = candidates.where(phone_number: phone_number) if phone_number.present?
      candidates = candidates.where('LOWER(name) ILIKE ?', "%#{name.to_s.downcase}%") if name.present?
      return true unless candidates.exists?(id: visible.select(:id))
    end

    false
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def connecta_scope_copilot_tool_denied?(conversation)
    return true if conversation.nil? || @user.nil?
    return false unless Connecta::Scope::Projection.marked?(conversation.inbox_id)

    !Connecta::Scope::Gate.new(@user).read?(conversation, access_path: 'copilot_tool')
  end
end
