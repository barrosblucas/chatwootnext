# frozen_string_literal: true

# Remove URLs de arquivo de payloads realtime de inbox marcada (spike G0, T0.2-c3).
#
# Causa raiz: `AttachmentUrlHook` emite `file_url`/`thumb_url`/`download_url` com o
# token do `Current.user` no momento da serializacao (o remetente). O listener
# (`ActionCableListener#message_created/#message_updated`) constroi UM hash e o
# `BroadcastJobGuard` reemite o MESMO conteudo para N destinatarios: o token do
# remetente vaza para todos e, apos o `ActiveStorageGuard` negar o legado com 404,
# a midia some para os demais viewers apos segundos (expiracao do token alheio).
#
# Correcao: no funil realtime de inbox marcada, o broadcast carrega anexos SEM
# `data_url`/`thumb_url`, preservando ids/tipo/metadados, com marcador explicito
# de resolucao. Cada viewer reidrata sua propria URL autorizada via GET autenticado
# existente (`MessageApi.getPreviousMessages`), que serializa com `Current.user`
# dele. Inbox nao marcada, widget e mailers nao passam por aqui.
#
# Modulo PURO: so opera sobre hashes/arrays, sem Rails/DB/`Current`. Quem decide o
# escopo (inbox marcada) e o chamador, via `Projection.marked?(inbox_id)` com os
# metadados ja em maos. Nao modifica o hash recebido: devolve o MESMO objeto
# quando nao ha o que remover (zero custo para inbox comum) e copias novas nos
# caminhos alterados, para nao afetar outro evento que compartilhe a estrutura.
module Connecta::Scope::MediaBroadcastSanitizer
  RESOLVE_MARKER = 'connecta_media_resolve'

  # Unicas chaves de URL que `Attachment#push_event_data` serializa para arquivo.
  # `location`/`fallback`/`embed` tambem usam `data_url` (com `external_url`): no
  # escopo marcado elas saem junto (fail-closed) e o GET autorizado as repoe; a
  # negacao do GET mantem o placeholder existente ate o proximo evento.
  FILE_URL_KEYS = %w[data_url thumb_url].freeze

  module_function

  # Verdadeiro quando o payload ja passou pelo sanitizador (idempotencia: o guard
  # pode rever um evento que o listener ja tratou; chaves chegam como symbol no
  # listener e como string apos a serializacao do job).
  def sanitized?(message)
    return false unless message.is_a?(Hash)

    value = message[RESOLVE_MARKER] || message[RESOLVE_MARKER.to_sym]
    value == true
  end

  # Sanitiza UM payload de mensagem. Devolve o mesmo objeto quando nao ha anexo
  # com URL de arquivo (inbox comum e tipos sem arquivo nao pagam copia).
  def sanitize_message(message)
    return message unless message.is_a?(Hash)

    attachments = message[:attachments] || message['attachments']
    return message unless attachments.is_a?(Array) && attachments.any? { |attachment| file_urls?(attachment) }

    copy = message.dup
    copy[marker_key_for(message)] = true
    if message.key?(:attachments)
      copy[:attachments] = attachments.map { |attachment| sanitize_attachment(attachment) }
    else
      copy['attachments'] = attachments.map { |attachment| sanitize_attachment(attachment) }
    end
    copy
  end

  # Sanitiza UM anexo. Devolve o mesmo objeto quando nao ha URL de arquivo.
  def sanitize_attachment(attachment)
    return attachment unless file_urls?(attachment)

    copy = attachment.is_a?(Hash) ? attachment.dup : attachment
    return attachment unless copy.is_a?(Hash)

    FILE_URL_KEYS.each do |key|
      copy.delete(key)
      copy.delete(key.to_sym)
    end
    copy[marker_key_for(attachment)] = true
    copy
  end

  # Sanitiza payload de conversa (cable `conversation.*`): `messages` (ultima) e
  # `last_non_activity_message` (preview da lista). Devolve o mesmo objeto quando
  # nada precisa sair. `UPDATE_CONVERSATION` do store ignora `messages`, mas
  # `ADD_CONVERSATION` usa o seed e o preview le `last_non_activity_message`.
  def sanitize_conversation(payload)
    return payload unless payload.is_a?(Hash)

    messages = payload[:messages] || payload['messages']
    last_message = payload[:last_non_activity_message] || payload['last_non_activity_message']
    return payload if messages.nil? && last_message.nil?

    sanitized_messages = messages.is_a?(Array) ? messages.map { |message| sanitize_message(message) } : messages
    sanitized_last = last_message.is_a?(Hash) ? sanitize_message(last_message) : last_message
    return payload if unchanged_messages?(messages, sanitized_messages) && sanitized_last.equal?(last_message)

    copy = payload.dup
    if payload.key?(:messages)
      copy[:messages] = sanitized_messages
    elsif payload.key?('messages')
      copy['messages'] = sanitized_messages
    end
    if payload.key?(:last_non_activity_message)
      copy[:last_non_activity_message] = sanitized_last
    elsif payload.key?('last_non_activity_message')
      copy['last_non_activity_message'] = sanitized_last
    end
    copy
  end

  def file_urls?(attachment)
    return false unless attachment.is_a?(Hash)

    FILE_URL_KEYS.any? do |key|
      value = attachment[key].nil? ? attachment[key.to_sym] : attachment[key]
      value.is_a?(String) && !value.empty?
    end
  end

  # Fail-closed para os rescues das barreiras (listener e job): devolve nil quando
  # o payload pode carregar URL de arquivo (marcado ou escopo desconhecido sob
  # falha); do contrário, o próprio payload (nada a vazar, ex. inbox comum sem
  # anexo). Puro: só percorre hashes/arrays, nunca levanta por lookup.
  def discard_unless_safe(payload)
    payload_may_carry_file_urls?(payload) ? nil : payload
  end

  def payload_may_carry_file_urls?(payload)
    return false unless payload.is_a?(Hash)

    attachments = payload[:attachments] || payload['attachments']
    return true if attachments.is_a?(Array) && attachments.any? { |attachment| file_urls?(attachment) }

    messages = payload[:messages] || payload['messages']
    return true if messages.is_a?(Array) && messages.any? { |message| payload_may_carry_file_urls?(message) }

    last_message = payload[:last_non_activity_message] || payload['last_non_activity_message']
    return true if last_message.is_a?(Hash) && payload_may_carry_file_urls?(last_message)

    false
  end

  # `Array#map` sempre devolve array novo: compara elemento a elemento para nao
  # copiar payload de conversa comum que so carrega mensagens sem URL de arquivo.
  def unchanged_messages?(messages, sanitized)
    return true if messages.nil? && sanitized.nil?
    return false unless messages.is_a?(Array) && sanitized.is_a?(Array)
    return false unless messages.length == sanitized.length

    sanitized.each_with_index.all? { |message, index| message.equal?(messages[index]) }
  end

  # O marcador segue o estilo de chave dominante do hash: symbol no listener
  # (vira string no JSON do cable/job), string dentro do job. Evita duplicar a
  # mesma chave nos dois estilos no mesmo hash.
  def marker_key_for(hash)
    hash.keys.first.is_a?(String) ? RESOLVE_MARKER : RESOLVE_MARKER.to_sym
  end
  private_class_method :marker_key_for
end
