# Prepend em ConversationFinder (instalado só pelo spike G0). O ramo participating troca a relação filtrada pelo Gate;
# aqui o ConversationQuery roda de novo sobre a relação trocada, antes de paginação e contagem.
module Connecta::Scope::ConversationFinderHook
  private

  def filter_by_conversation_type
    super
    return @conversations unless params[:conversation_type] == 'participating'

    @conversations = Connecta::Scope::ConversationQuery.new(@conversations, current_user).perform
  end
end
