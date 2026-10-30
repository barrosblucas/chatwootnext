# Decide leitura e escrita humanas em conversas de inboxes marcadas. Negação por padrão.
# Admin nominal da projeção só lê, com auditoria; agente nativo nunca vira admin por causa do papel.
# Administrador NATIVO da conta do recurso (helpers Connecta::Scope::NativeAdmin) tem full
# same-account em leitura e escrita, após prova account do recurso; cross-account sempre nega.
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

  # Notificação e menção não são leitura por detalhe: admin nominal fica de fora, mesmo quando o Gate lhe daria leitura.
  def notifiable?(conversation)
    !@projection.admin? && agent_allowed?(conversation, :read)
  end

  # Revalidação de destinatário de contato excluído (DeliveryCheck): mesma regra de
  # leitura que o Gate usa internamente; exposto só para esse chamador.
  def readable_scope?(scope)
    scope_readable?(scope)
  end

  private

  def decide(conversation, action, access_path)
    allowed = native_admin_authorized?(conversation) || (@projection.admin? ? action == :read : agent_allowed?(conversation, action))
    Connecta::Scope::AccessAudit.create!(
      user_id: @user.id, conversation_id: conversation.id, surface: 'conversation',
      access_path: access_path, decision: allowed ? 'allow' : 'deny'
    )
    allowed
  end

  # Administrador nativo full same-account: vínculo ATUAL de administrator na
  # conta DA CONVERSA (reconsultado a cada chamada). Recurso de outra conta
  # nunca libera. Não depende de grant setorial nem amplia admin_nominal.
  def native_admin_authorized?(conversation)
    Connecta::Scope::NativeAdmin.authorized_for?(@user, conversation)
  end

  def agent_allowed?(conversation, action)
    scope_allowed?(Connecta::Scope::ConversationScope.find_by(conversation_id: conversation.id), conversation.inbox_id, action)
  end

  # T3.9: manutenção bloqueia o envio humano (write) com 409. Entrada continua
  # gravada (o ingresso não passa por write?); leitura segue a regra normal.
  def maintenance_denial?(inbox_id, action)
    return false unless action == :write

    inbox = Connecta::Scope::ScopedInbox.find_by(inbox_id: inbox_id)
    inbox.present? && inbox.maintenance_mode?
  end

  def scope_readable?(scope)
    !@projection.admin? && scope_allowed?(scope, scope.inbox_id, :read)
  end

  # Setor do grant ou um ancestral dele: o caminho do setor da conversa começa pelo caminho do grant.
  def granted_sector?(scope, action)
    permissions = action == :read ? READ_PERMISSIONS : WRITE_PERMISSIONS
    @projection.granted_paths(permissions).any? { |path| scope.org_unit.path.start_with?(path) }
  end

  def enforced?(inbox_id)
    scoped_inbox = Connecta::Scope::ScopedInbox.find_by(inbox_id: inbox_id)
    return false if scoped_inbox.nil?

    # T3.9 admin_only: a inbox continua marcada e o servidor nega toda
    # superfície escopada a não-admin (membro ou team_id forçado não basta).
    # maintenance não desmarca: entrada continua gravada, envio nega com 409.
    return true if scoped_inbox.admin_only?
    return true if scoped_inbox.maintenance_mode?

    scoped_inbox.enforcement == 'enforce'
  end

  # T3.9: em maintenance, escrita humana nega com 409 (entrada segue gravada).
  # Público para o guard HTTP traduzir em 409 (Denied :conflict).
  def maintenance_conflict?(scope, action)
    return false unless action == :write
    return false if scope.nil?

    Connecta::Scope::ScopedInbox.where(inbox_id: scope.inbox_id).exists?(
      ['maintenance = ? OR enforcement = ?', true, 'maintenance']
    )
  end

  def state_allows?(scope, action)
    return Connecta::Scope::ConversationScope::READ_STATES.include?(scope.state) if action == :read

    # T3.9 maintenance: a conversa continua gravada no banco (ingresso), mas
    # escrita/envio humano nega com 409. Escopo fora de active nega junto.
    return false if maintenance_inbox?(scope.inbox_id)

    scope.state == 'active' && scope.case_version.positive?
  end

  def maintenance_inbox?(inbox_id)
    Connecta::Scope::ScopedInbox.where(inbox_id: inbox_id).exists?(
      ['maintenance = ? OR enforcement = ?', true, 'maintenance']
    )
  end

  # Cadeia de negação por padrão (enforcement, admin_only, manutenção, grant); cada ramo nega.
  def scope_allowed?(scope, inbox_id, action) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return false unless scope && enforced?(inbox_id) && scope.org_unit.enabled?
    # T3.9 admin_only: não-admin nega em TODAS as superfícies já hookadas —
    # membresia da inbox ou team_id forçado não bastam (a policy nativa
    # liberaria por inbox_access?/team_access?; aqui o Gate nega antes).
    return @projection.admin? && action == :read if Connecta::Scope::ScopedInbox.exists?(inbox_id: inbox_id, enforcement: 'admin_only')
    # Manutenção nega leitura de não-admin no detalhe (a lista já exclui a inbox: ConversationQuery#enforced_inbox_ids).
    return false if !@projection.admin? && maintenance_inbox?(inbox_id)

    @projection.verified? && @projection.fresh? && state_allows?(scope, action) && granted_sector?(scope, action)
  end
end
