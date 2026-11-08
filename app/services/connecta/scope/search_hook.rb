# Prepend em SearchService (instalado só pelo spike G0). Mensagens, conversas e contatos de inbox marcada entram na busca só se visíveis,
# antes de paginação. filter_conversations e filter_contacts são cópias mínimas do original com o escopo aplicado: manter em sincronia.
module Connecta::Scope::SearchHook
  private

  def message_base_query
    super.where(conversation_id: scoped_conversations.select(:id))
  end

  def filter_conversations
    base = scoped_conversations.where(inbox_id: accessable_inbox_ids)
    message_ids = base.joins('INNER JOIN contacts ON conversations.contact_id = contacts.id')
                      .where('cast(conversations.display_id as text) ILIKE :search OR contacts.name ILIKE :search OR ' \
                             'contacts.email ILIKE :search OR contacts.phone_number ILIKE :search OR ' \
                             'contacts.identifier ILIKE :search', search: "%#{search_query}%")
                      .select(:id)
    protocol_ids = Connecta::Scope::ProtocolSearch.apply(base, search_query).select(:id)
    conversations_query = base.where(id: message_ids).or(base.where(id: protocol_ids))

    if current_account.feature_enabled?('advanced_search')
      conversations_query = apply_time_filter(conversations_query, 'conversations.last_activity_at')
    end

    @conversations = conversations_query.order('conversations.created_at DESC').page(params[:page]).per(15)
  end

  def filter_contacts
    contacts_query = Connecta::Scope::ContactVisibility.visible_scope(current_account, current_user).where(
      'name ILIKE :search OR email ILIKE :search OR phone_number ILIKE :search OR identifier ILIKE :search', search: "%#{search_query}%"
    )

    contacts_query = apply_time_filter(contacts_query, 'last_activity_at') if current_account.feature_enabled?('advanced_search')

    @contacts = contacts_query.resolved_contacts(use_crm_v2: current_account.feature_enabled?('crm_v2'))
                              .order_on_last_activity_at('desc').page(params[:page]).per(15)
  end

  def scoped_conversations
    Connecta::Scope::ConversationQuery.new(current_account.conversations, current_user).perform
  end
end
