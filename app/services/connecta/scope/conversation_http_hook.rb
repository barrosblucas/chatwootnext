# Prepend em Api::V1::Accounts::ConversationsController e Api::V1::Accounts::Conversations::BaseController (instalado só pelo spike G0).
# Autenticado em inbox marcada: leitura negada vira 404, escrita e criação negadas viram 403. Não autenticado segue para o 401 nativo.
module Connecta::Scope::ConversationHttpHook
  private

  # Leitura: o show? nativo negaria com 401. Em inbox marcada a conversa não é revelada (404). Inbox não marcada segue nativa.
  def conversation
    super
  rescue Pundit::NotAuthorizedError
    raise unless Connecta::Scope::Projection.marked?(@conversation.inbox_id)

    raise Connecta::Scope::Denied, :not_found
  end

  # Qualquer escrita (método que não seja GET) em conversa de inbox marcada: só agente com grant na etapa active e versão válida.
  # Transcrição não escreve na conversa (envia por e-mail) e tem guarda própria.
  # team_id é proibido na inbox marcada (T0.2-c6, parte a): depois da escrita autorizada, presença do parâmetro
  # (inclusive null/mesmo valor, inclusive aninhado) vira 422. Fora do escopo continua 404/403 sem revelar existência.
  # Presença, anexos, Copilot e contato excluído não são tocados aqui.
  # T3.9 maintenance: a escrita humana nega com 409 quando a inbox está em
  # manutenção (a entrada continua gravada pelo ingresso). O check vem antes
  # do team_id: manutenção é contenção de envio, não erro de parâmetro.
  def connecta_scope_write_guard!
    return if request.get? || action_name == 'transcript' || @conversation.nil? || !Connecta::Scope::Projection.marked?(@conversation.inbox_id)
    return connecta_scope_maintenance_guard! if connecta_scope_maintenance_denial?
    return if connecta_scope_resolved_reopen_allowed?
    return connecta_scope_resolved_guard! if connecta_scope_resolved_denial?
    return connecta_scope_team_guard! if Connecta::Scope::Gate.new(Current.user).write?(@conversation, access_path: connecta_scope_access_path)

    raise Connecta::Scope::Denied, :forbidden
  end

  # team_id proibido na inbox marcada (matriz 10.1, T0.2-c6 parte a): só roda depois da escrita autorizada,
  # para não ampliar acesso nem revelar existência (fora do escopo continua 404/403 pelo caminho nativo).
  # Presença do parâmetro (inclusive null/mesmo valor, inclusive aninhado) é tentativa e vira 422; nada é gravado.
  def connecta_scope_team_guard!
    return unless connecta_scope_team_param?

    Connecta::Scope::AccessAudit.create!(user_id: Current.user.id, conversation_id: @conversation.id, surface: 'conversation',
                                         access_path: "#{connecta_scope_access_path}_team", decision: 'deny')
    raise Connecta::Scope::Denied, :unprocessable_entity
  end

  # T3.9 maintenance: a conversa continua gravando a entrada (ingresso pelo
  # webhook/canal), mas o envio humano responde 409 com auditoria de negação.
  def connecta_scope_maintenance_guard!
    Connecta::Scope::AccessAudit.create!(user_id: Current.user.id, conversation_id: @conversation.id, surface: 'conversation',
                                         access_path: "#{connecta_scope_access_path}_maintenance", decision: 'deny')
    raise Connecta::Scope::Denied, :conflict
  end

  # Conversa resolvida (decisão 005): toda escrita nega com 403, inclusive para
  # administrador nativo e usuário de serviço — só a reabertura explícita
  # (toggle_status para open, com leitura ou admin nativo) passa. A mensagem de
  # negação segue a do Denied (:forbidden). Leitura continua permitida (o show é
  # GET e `closed` está em READ_STATES).
  def connecta_scope_resolved_denial?
    @conversation.resolved? && Connecta::Runtime::Feature.enabled?
  end

  def connecta_scope_resolved_guard!
    Connecta::Scope::AccessAudit.create!(user_id: Current.user.id, conversation_id: @conversation.id, surface: 'conversation',
                                         access_path: "#{connecta_scope_access_path}_resolved", decision: 'deny')
    raise Connecta::Scope::Denied, :forbidden
  end

  # Reabertura explícita pelo operador: toggle_status para open em conversa
  # resolvida, por quem tem leitura no atendimento (grant com `closed` legível)
  # ou admin nativo same-account. Qualquer outra escrita em resolvida nega.
  def connecta_scope_resolved_reopen_allowed?
    return false unless @conversation.resolved?
    return false unless action_name == 'toggle_status'
    return false unless Connecta::Runtime::Feature.enabled?

    target = params[:status].presence || @conversation.toggled_status.to_s
    return false unless target == 'open'

    Connecta::Scope::NativeAdmin.authorized_for?(Current.user, @conversation) ||
      Connecta::Scope::Gate.new(Current.user).read?(@conversation, access_path: "#{connecta_scope_access_path}_reopen")
  end

  def connecta_scope_maintenance_denial?
    scope = Connecta::Scope::ConversationScope.find_by(conversation_id: @conversation.id)
    return false if scope.nil?

    Connecta::Scope::ScopedInbox.where(inbox_id: scope.inbox_id).exists?(
      ['maintenance = ? OR enforcement = ?', true, 'maintenance']
    )
  end

  def connecta_scope_team_param?
    connecta_scope_deep_key?(params.to_unsafe_h, 'team_id')
  end

  def connecta_scope_deep_key?(node, key)
    case node
    when Hash
      node.any? { |k, v| k.to_s == key || connecta_scope_deep_key?(v, key) }
    when Array
      node.any? { |element| connecta_scope_deep_key?(element, key) }
    else
      false
    end
  end

  # Transcrição envia o conteúdo da conversa por e-mail: em inbox marcada, admin
  # nominal (leitura auditada pelo detalhe) ou administrador nativo same-account.
  def connecta_scope_transcript_guard!
    return unless Connecta::Scope::Projection.marked?(@conversation.inbox_id)

    allowed = Connecta::Scope::Projection.new(current_user).admin? ||
              Connecta::Scope::NativeAdmin.authorized_for?(current_user, @conversation)
    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: @conversation.id, surface: 'conversation',
                                         access_path: 'conversation_transcript', decision: allowed ? 'allow' : 'deny')
    raise Connecta::Scope::Denied, :forbidden unless allowed
  end

  # Transferência legada (Connecta::TransferService) não roda no spike: nega antes do proxy HTTP. O T0.3 entrega a transferência local.
  # Com o runtime de número humano ligado, a autorização é do TransferPolicy (ator, grant `transferir`, escopo).
  # Este guard negaria antes dele, e o 403 do contrato de runtime não viria da regra de transferência.
  def connecta_scope_transfer_guard!
    return if Connecta::Runtime::Feature.enabled?

    raise Connecta::Scope::Denied, :forbidden if Connecta::Scope::Projection.marked?(@conversation.inbox_id)
  end

  def connecta_scope_access_path
    "#{controller_name.singularize}_#{action_name}"
  end
end
