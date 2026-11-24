# Prepend em ConversationFinder (instalado só pelo spike G0). O ramo participating troca a relação filtrada pelo Gate;
# aqui o ConversationQuery roda de novo sobre a relação trocada, antes de paginação e contagem. O ramo bot estreita a
# mesma relação autorizada às conversas com triagem ativa confirmada pela plataforma (leitura ponto no tempo, sem
# atomicidade entre serviços); falha fechada com 503 via BotEligibility::Unavailable, nunca parcial. O guarda de
# reentrância cobre install! repetido em suíte (mesmo processo): sem ele a plataforma seria chamada duas vezes.
# A exclusão opt-in da fila humana (`exclude_active_bot=true`) estreita a
# relação já autorizada ao atendimento ativo corrente nas inboxes marcadas
# (escopo `active` + protocolo + unidade habilitada), antes de
# status/contagens/paginação. Só na lista aberta padrão (sem tipo de conversa, sem busca): outras visões nunca
# disparam lookup externo por acidente. Sem rede no caminho humano: erro de
# banco preserva a lista e sinaliza via `bot_classification_unavailable`.
# As abas do dashboard Connecta (`connecta_dashboard=true` + `connecta_tab`)
# rodam no mesmo ponto pré-contagem via DashboardTabs e subsumem a partição
# humano/Bot; sob opt-in, `exclude_active_bot`, `assignee_type` e
# `conversation_type` nativos são ignorados para lista e contagem concordarem.
module Connecta::Scope::ConversationFinderHook
  private

  def find_all_conversations
    super
    if Connecta::Scope::DashboardTabs.opt_in?(params)
      @conversations = Connecta::Scope::DashboardTabs.apply(
        @conversations, user: current_user, account: current_account, params: params
      )
    else
      apply_bot_exclusion if bot_exclusion_requested?
    end
    @conversations
  end

  def filter_by_conversation_type
    return @conversations if Connecta::Scope::DashboardTabs.opt_in?(params)

    super
    case params[:conversation_type]
    when 'participating'
      @conversations = Connecta::Scope::ConversationQuery.new(@conversations, current_user).perform
    when 'bot'
      unless @_connecta_bot_applied
        @_connecta_bot_applied = true
        @conversations = Connecta::Scope::BotEligibility.new(@conversations).perform
      end
    end
    @conversations
  end

  def filter_by_assignee_type
    return @conversations if Connecta::Scope::DashboardTabs.opt_in?(params)

    super
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

  def bot_exclusion_requested?
    params[:exclude_active_bot] == 'true' &&
      (params[:status].nil? || params[:status] == 'open') &&
      params[:q].blank? &&
      params[:conversation_type].blank?
  end

  def apply_bot_exclusion
    result = Connecta::Scope::BotEligibility.exclude_from(@conversations)
    @conversations = result[:relation]
    @bot_classification_unavailable = result[:unavailable]
  end
end
