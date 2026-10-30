# Prepend em Api::V1::Accounts::Conversations::DirectUploadsController (instalado só pelo spike G0, test-only).
# O controller herda ActiveStorage::DirectUploadsController, então o hook central de conversa não roda aqui.
# Guarda roda depois da autenticação nativa e do carregamento da conta, antes de criar o blob (sem signed_id/URL
# antes de autorizar). Conversa resolvida sempre no account ativo (IDs de outra conta não dão acesso). Inbox
# marcada: leitura negada vira 404, escrita negada vira 403 (contrato Gate/auditoria). Inbox não marcada: nativo.
module Connecta::Scope::DirectUploadsHook
  private

  def create
    connecta_scope_direct_upload_guard!
    super
  end

  def connecta_scope_direct_upload_guard!
    return unless current_user

    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id])
    raise Connecta::Scope::Denied, :not_found if conversation.nil?
    return unless Connecta::Scope::Projection.marked?(conversation.inbox_id)

    gate = Connecta::Scope::Gate.new(current_user)
    raise Connecta::Scope::Denied, :not_found unless gate.read?(conversation, access_path: 'direct_upload')
    raise Connecta::Scope::Denied, :forbidden unless gate.write?(conversation, access_path: 'direct_upload')
  end
end
