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
      existing = @conversation.messages.find_by(
        "content_attributes ->> '#{NONCE_KEY}' = ?", nonce
      )
      if existing
        @message = existing
        render :create, status: :ok
      else
        super
      end
    end
  end

  private

  def connecta_followup_nonce
    raw = params[:content_attributes]
    data = raw.is_a?(String) ? JSON.parse(raw) : raw
    nonce = data.respond_to?(:[]) ? (data[NONCE_KEY] || data[NONCE_KEY.to_sym]) : nil
    nonce = nonce.to_s
    return nil if nonce.empty? || nonce.length > MAX_NONCE_LENGTH

    nonce
  rescue JSON::ParserError, TypeError
    nil
  end
end
