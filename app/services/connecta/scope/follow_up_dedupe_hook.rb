# Dedupe dos anexos de acompanhamento da admissão manual. O browser envia um
# nonce estável em content_attributes; o endpoint nativo de mensagens (caminho
# oficial) devolve a mensagem existente em vez de duplicar em retry/perda de
# resposta. Sem nonce, o fluxo nativo segue intocado.
module Connecta::Scope::FollowUpDedupeHook
  NONCE_KEY = 'connecta_followup_nonce'.freeze
  MAX_NONCE_LENGTH = 200

  def create
    nonce = connecta_followup_nonce
    return super if nonce.nil?

    @conversation.with_lock do
      existing = find_follow_up(nonce)
      if existing
        @message = existing
        render :create, status: :ok
      else
        super
      end
    end
  end

  private

  # O filtro textual só reduz candidatos (a coluna é `json` e aceita escalar,
  # array, null e o formato serializado legado). A comparação final é feita em
  # Ruby, então um documento que não seja objeto nunca derruba o endpoint nem
  # entra no dedupe.
  def find_follow_up(nonce)
    @conversation.messages
                 .where('content_attributes::text LIKE ?', "%#{NONCE_KEY}%")
                 .find { |message| follow_up_nonce(raw_content_attributes(message)) == nonce }
  end

  # O reader do model normaliza não-Hash para {}; o formato serializado legado
  # só é visível no valor bruto da coluna. O parser aceita objeto ou string JSON
  # com objeto dentro.
  def raw_content_attributes(message)
    message.read_attribute_before_type_cast(:content_attributes)
  end

  def follow_up_nonce(value)
    data = decode_follow_up_attributes(value)
    return nil unless data.is_a?(Hash)

    nonce = data[NONCE_KEY] || data[NONCE_KEY.to_sym]
    nonce.is_a?(String) ? nonce.presence : nil
  end

  # Aceita o objeto já decodificado pelo tipo json e o formato serializado em
  # que a coluna guarda uma string JSON contendo o objeto (duas decodificações).
  def decode_follow_up_attributes(value)
    data = value
    2.times do
      break unless data.is_a?(String)

      data = JSON.parse(data)
    end
    data
  rescue JSON::ParserError, TypeError
    nil
  end

  def connecta_followup_nonce
    nonce = follow_up_nonce_from_params
    return nil unless nonce.is_a?(String) && nonce.length.between?(1, MAX_NONCE_LENGTH)

    nonce
  end

  def follow_up_nonce_from_params
    raw = params[:content_attributes]
    data = raw.is_a?(String) ? JSON.parse(raw) : raw
    return nil unless data.respond_to?(:[])

    data[NONCE_KEY] || data[NONCE_KEY.to_sym]
  rescue JSON::ParserError, TypeError
    nil
  end
end
