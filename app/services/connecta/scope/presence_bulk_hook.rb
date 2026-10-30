# Prepend em Api::V1::Accounts::ConversationsController (instalado só pelo spike G0, test-only).
# Guarda do bulk de presença: roda depois da autenticação nativa e antes do serviço, resolve display_ids
# na conta do request (sem consulta global). Todo alvo marcado exige as MESMAS permissões de
# leitura/escrita/estado da presença unitária (leitura negada vira 404, escrita negada vira 403).
# Lote misto com alvo marcado não autorizado nega antes de qualquer chamada ao serviço/provedor
# (sem efeito parcial). Só unmarked segue nativo; autorizado marcado segue serviço nativo (limite 10).
module Connecta::Scope::PresenceBulkHook
  private

  def connecta_scope_presence_bulk_guard!
    return unless current_user

    ids = Array(presence_subscribe_params[:conversation_ids]).first(10)
    return if ids.empty?

    targets = Current.account.conversations.where(display_id: ids).to_a
    marked = targets.select { |conversation| Connecta::Scope::Projection.marked?(conversation.inbox_id) }
    return if marked.empty?

    gate = Connecta::Scope::Gate.new(current_user)
    deny_unread_presence_bulk!(gate, marked)
    deny_unwritable_presence_bulk!(gate, marked)
  end

  # Negação em duas fases (leitura 404, depois escrita 403): loops separados, não fundir — fundir mudaria a semântica do lote.
  # Leitura negada vira 404 antes de qualquer checagem de escrita.
  def deny_unread_presence_bulk!(gate, marked)
    marked.each do |conversation|
      raise Connecta::Scope::Denied, :not_found unless gate.read?(conversation, access_path: 'conversation_presence_subscribe_bulk')
    end
  end

  # Escrita negada vira 403 depois que todas as leituras passaram.
  def deny_unwritable_presence_bulk!(gate, marked)
    marked.each do |conversation|
      raise Connecta::Scope::Denied, :forbidden unless gate.write?(conversation, access_path: 'conversation_presence_subscribe_bulk')
    end
  end
end
