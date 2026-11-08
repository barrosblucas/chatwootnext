# Prepend em ConversationFinder (instalado só pelo spike G0). O ramo participating troca a relação filtrada pelo Gate;
# aqui o ConversationQuery roda de novo sobre a relação trocada, antes de paginação e contagem.
module Connecta::Scope::ConversationFinderHook
  private

  def filter_by_conversation_type
    super
    return @conversations unless params[:conversation_type] == 'participating'

    @conversations = Connecta::Scope::ConversationQuery.new(@conversations, current_user).perform
  end

  # A busca da lista nativa procura só conteúdo de mensagem. Aqui a mesma
  # relação (já passou por ConversationQuery em find_all_conversations) ganha
  # OR por protocolo. A subquery de protocolo continua sobre @conversations,
  # portanto nunca amplia conta, inbox ou grant.
  def filter_by_query
    return super unless params[:q]

    message_ids = @conversations.joins(:messages)
                                .where('messages.content ILIKE :search', search: "%#{params[:q]}%")
                                .where(messages: { message_type: [Message.message_types[:incoming],
                                                                  Message.message_types[:outgoing]] })
                                .select(:id)
    protocol_ids = Connecta::Scope::ProtocolSearch.apply(@conversations, params[:q]).select(:id)
    @conversations = @conversations.where(id: message_ids).or(@conversations.where(id: protocol_ids)).includes(:messages)
  end
end
