# Restringe a relação de conversas ANTES de paginação e contagem. Conversas de inboxes não marcadas seguem a relação nativa.
class Connecta::Scope::ConversationQuery
  def initialize(relation, user)
    @relation = relation
    @user = user
    @projection = Connecta::Scope::Projection.new(user)
  end

  def perform
    marked_ids = Connecta::Scope::Projection.marked_inbox_ids
    return @relation if marked_ids.empty?
    return admin_listing(marked_ids) if @projection.admin?

    @relation.where.not(inbox_id: marked_ids).or(@relation.where(id: visible_conversation_ids))
  end

  private

  # Admin nominal não recebe linhas da inbox marcada na listagem: o conteúdo de cada conversa sai só pelo detalhe, auditado por conversa.
  # O registro com conversation_id nulo prova apenas que a listagem foi consultada, não que houve leitura de conteúdo.
  def admin_listing(marked_ids)
    Connecta::Scope::AccessAudit.create!(
      user_id: @user.id, conversation_id: nil, surface: 'conversation', access_path: 'list', decision: 'allow'
    )
    @relation.where.not(inbox_id: marked_ids)
  end

  # Sem verificação ou projeção vencida, a lista de caminhos fica vazia e `LIKE ANY` não casa nenhuma linha.
  def visible_conversation_ids
    Connecta::Scope::ConversationScope.joins(:org_unit)
                                      .where(state: Connecta::Scope::ConversationScope::READ_STATES, inbox_id: enforced_inbox_ids)
                                      .where(connecta_g0_org_units: { enabled: true })
                                      .where('connecta_g0_org_units.path LIKE ANY (ARRAY[?]::text[])', read_path_patterns)
                                      .select(:conversation_id)
  end

  def read_path_patterns
    return [] unless @projection.verified? && @projection.fresh?

    @projection.granted_paths(Connecta::Scope::Gate::READ_PERMISSIONS).map { |path| "#{path}%" }
  end

  def enforced_inbox_ids
    Connecta::Scope::ScopedInbox.where(enforcement: 'enforce', maintenance: false).select(:inbox_id)
  end
end
