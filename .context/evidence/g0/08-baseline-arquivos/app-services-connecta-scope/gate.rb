# Decide leitura e escrita humanas em conversas de inboxes marcadas. Negação por padrão.
# Admin nominal da projeção só lê, com auditoria; agente nativo nunca vira admin por causa do papel.
# Só deve ser chamado para inboxes marcadas (os hooks verificam antes).
class Connecta::Scope::Gate
  READ_PERMISSIONS = %w[acompanhar atender].freeze
  WRITE_PERMISSIONS = %w[atender].freeze

  def initialize(user)
    @user = user
    @projection = Connecta::Scope::Projection.new(user)
  end

  def read?(conversation, access_path:)
    decide(conversation, :read, access_path)
  end

  def write?(conversation, access_path:)
    decide(conversation, :write, access_path)
  end

  private

  def decide(conversation, action, access_path)
    allowed = @projection.admin? ? action == :read : agent_allowed?(conversation, action)
    Connecta::Scope::AccessAudit.create!(
      user_id: @user.id, conversation_id: conversation.id, surface: 'conversation',
      access_path: access_path, decision: allowed ? 'allow' : 'deny'
    )
    allowed
  end

  def agent_allowed?(conversation, action)
    scope = Connecta::Scope::ConversationScope.find_by(conversation_id: conversation.id)
    return false unless scope && enforced?(conversation.inbox_id) && scope.org_unit.enabled?

    @projection.verified? && @projection.fresh? && state_allows?(scope, action) && granted_sector?(scope, action)
  end

  # Setor do grant ou um ancestral dele: o caminho do setor da conversa começa pelo caminho do grant.
  def granted_sector?(scope, action)
    permissions = action == :read ? READ_PERMISSIONS : WRITE_PERMISSIONS
    @projection.granted_paths(permissions).any? { |path| scope.org_unit.path.start_with?(path) }
  end

  def enforced?(inbox_id)
    scoped_inbox = Connecta::Scope::ScopedInbox.find_by(inbox_id: inbox_id)
    scoped_inbox&.enforcement == 'enforce' && !scoped_inbox.maintenance
  end

  def state_allows?(scope, action)
    return Connecta::Scope::ConversationScope::READ_STATES.include?(scope.state) if action == :read

    scope.state == 'active' && scope.case_version.positive?
  end
end
