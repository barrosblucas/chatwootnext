# Token curto para download de anexo de conversa marcada (spike G0, T0.2-c3). NÃO é produto de mídia.
# Assinado com o message_verifier "ActiveStorage" do Rails (mecanismo existente, sem credencial nova).
# Vínculos no payload: attachment_id, blob_id, user_id, account_id e epoch do usuário no momento da emissão.
# Expiração curta embutida no envelope assinado (expires_in). Revogação/transferência invalida mesmo sem expirar:
# o download relê user, conta, epoch e Gate a cada requisição. Conhecer URL/token nunca basta.
module Connecta::Scope::AttachmentToken
  PURPOSE = 'connecta_g0_attachment_download'.freeze
  TTL = 5.minutes.freeze

  def self.issue(attachment:, user:, account:, epoch:)
    payload = {
      'attachment_id' => attachment.id,
      'blob_id' => attachment.file.blob.id,
      'user_id' => user.id,
      'account_id' => account.id,
      'epoch' => epoch
    }
    Rails.application.message_verifier('ActiveStorage').generate(payload, purpose: PURPOSE, expires_in: TTL)
  end

  def self.read(token)
    Rails.application.message_verifier('ActiveStorage').verified(token, purpose: PURPOSE)
  end
end
