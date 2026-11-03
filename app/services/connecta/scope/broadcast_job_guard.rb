# Revalida destinatários e projeta o payload recarregado pelo job nativo.
module Connecta::Scope::BroadcastJobGuard
  private

  def connecta_scope_capture
    Connecta::Scope::DeliveryContext.take(self.class.name)
  end

  def perform(members, event_name, data)
    context = @connecta_scope_context
    allowed = Connecta::Scope::DeliveryCheck.allowed_tokens(context, members, event_name, data)
    return if allowed.blank?

    super(allowed, event_name, data)
  end

  def prepare_broadcast_data(event_name, data)
    prepared = super
    context = @connecta_scope_context
    projected = Connecta::Scope::ContactDataProjection.socket_payload(
      prepared, force_contact: context.is_a?(Hash) && context['kind'] == 'contact_deleted'
    )
    connecta_scope_sanitize_media(projected, event_name: event_name)
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    # Descarte fail-closed da barreira de midia: nil significa "nao transmitir".
    # O motivo ja foi registrado no ponto do descarte, sem payload/segredo.
    return if broadcast_data.nil?

    super
  end

  # Segunda barreira (idempotente + fail-closed): o listener ja trata `message.created/updated`,
  # e `first_reply_created` (sem consumidor no FE) tambem passa por aqui, assim como
  # payloads de conversa recarregados (`CONVERSATION_UPDATE_EVENTS`) e eventos por
  # caminhos sem o listener. Nativo só para inbox confirmadamente nao marcada: sem
  # prova de marcado (lookup falhou, inbox ausente) ou com falha na sanitizacao,
  # descarta (nil) quando houver URL de arquivo em jogo; sem URL, devolve intacto.
  # Nunca propaga excecao nem devolve o original com URL para o broadcast nativo.
  def connecta_scope_sanitize_media(payload, event_name: nil)
    return payload unless payload.is_a?(Hash)

    return payload if Connecta::Scope::MediaBroadcastSanitizer.sanitized?(payload)

    marked = connecta_scope_payload_marked?(payload)
    return payload if marked == false
    return Connecta::Scope::MediaBroadcastSanitizer.discard_unless_safe(payload) if marked.nil?

    if connecta_scope_message_payload?(payload)
      Connecta::Scope::MediaBroadcastSanitizer.sanitize_message(payload)
    else
      Connecta::Scope::MediaBroadcastSanitizer.sanitize_conversation(payload)
    end
  rescue StandardError => e
    connecta_scope_report_media_discard(payload, event_name: event_name, error: e)
    Connecta::Scope::MediaBroadcastSanitizer.discard_unless_safe(payload)
  end

  # true = marcada, false = confirmadamente nao marcada, nil = escopo desconhecido.
  def connecta_scope_payload_marked?(payload)
    if connecta_scope_message_payload?(payload)
      inbox_id = connecta_scope_message_inbox_id(payload)
      return if inbox_id.nil?

      return Connecta::Scope::Projection.marked?(inbox_id)
    end

    inbox_id = payload[:inbox_id] || payload['inbox_id']
    return if inbox_id.nil?

    Connecta::Scope::Projection.marked?(inbox_id)
  end

  # Log operacional sem segredo: so IDs e classe do erro. Nunca payload, token ou URL.
  def connecta_scope_report_media_discard(payload, event_name:, error:)
    account_id = payload[:account_id] || payload['account_id']
    display_id = payload[:conversation_id] || payload['conversation_id'] || payload[:id] || payload['id']
    message_id = payload[:message_id] || payload['message_id'] || payload[:id] || payload['id']
    Rails.logger.warn(
      "[connecta_scope] realtime media broadcast descartado event=#{event_name} " \
      "account_id=#{account_id} conversation_id=#{display_id} message_id=#{message_id} error=#{error.class}"
    )
  end

  def connecta_scope_message_payload?(payload)
    attachments = payload[:attachments] || payload['attachments']
    attachments.is_a?(Array)
  end

  # `conversation_id` no cable de mensagem e o `display_id`; resolve o vinculo
  # vivo sem carregar a conversa quando ja marcada/ausente de anexos.
  def connecta_scope_message_inbox_id(payload)
    conversation_id = payload[:conversation_id] || payload['conversation_id']
    account_id = payload[:account_id] || payload['account_id']
    return if conversation_id.nil? || account_id.nil?

    account = Account.find_by(id: account_id)
    account&.conversations&.find_by(display_id: conversation_id)&.inbox_id
  end
end
