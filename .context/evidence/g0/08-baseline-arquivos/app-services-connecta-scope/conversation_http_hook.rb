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
  def connecta_scope_write_guard!
    return if request.get? || @conversation.nil? || !Connecta::Scope::Projection.marked?(@conversation.inbox_id)
    return if Connecta::Scope::Gate.new(Current.user).write?(@conversation, access_path: connecta_scope_access_path)

    raise Connecta::Scope::Denied, :forbidden
  end

  # Criação em inbox marcada é admissão única (fora deste spike). Vale para o inbox_id e para o inbox alcançado pelo source_id,
  # que o controller também resolve. Roda antes de qualquer I/O; não autenticado segue para o 401 nativo.
  def connecta_scope_create_guard!
    return unless current_user

    inbox_ids = [params[:inbox_id]]
    inbox_ids += ::ContactInbox.where(source_id: params[:source_id]).pluck(:inbox_id) if params[:source_id].present?
    return unless inbox_ids.any? { |inbox_id| Connecta::Scope::Projection.marked?(inbox_id) }

    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'conversation',
                                         access_path: connecta_scope_access_path, decision: 'deny')
    raise Connecta::Scope::Denied, :forbidden
  end

  # Transferência legada (Connecta::TransferService) não roda no spike: nega antes do proxy HTTP. O T0.3 entrega a transferência local.
  def connecta_scope_transfer_guard!
    raise Connecta::Scope::Denied, :forbidden if Connecta::Scope::Projection.marked?(@conversation.inbox_id)
  end

  def connecta_scope_denied(error)
    render json: { error: error.message }, status: error.status
  end

  def connecta_scope_access_path
    "#{controller_name.singularize}_#{action_name}"
  end
end
