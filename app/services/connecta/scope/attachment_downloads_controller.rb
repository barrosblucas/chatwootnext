# Download autorizado de anexo de conversa marcada (spike G0, T0.2-c3). Rota desenhada só pelo Installer em
# Rails.env.test?; fora dos specs G0 este controller nunca recebe requisição. Herda Api::V1::Accounts::BaseController:
# sem sessão/token válido, o 401 nativo sai antes do show; conta errada não resolve (find pelo Current.account).
# Revalida a cada requisição: token assinado (attachment/blob/usuário/conta/epoch/expiração), epoch viva no banco
# e Gate de leitura da conversa. Revogação/transferência invalida mesmo com token não expirado. Negado vira 404
# (leitura; decisão 002). Serve os bytes pelo próprio app — nunca redirect para URL global de blob.
class Connecta::Scope::AttachmentDownloadsController < Api::V1::Accounts::BaseController
  def show
    attachment = ::Attachment.where(account_id: Current.account.id).find_by(id: params[:attachment_id])
    raise Connecta::Scope::Denied, :not_found if attachment.nil? || !attachment.file.attached?

    conversation = attachment.message.conversation
    raise Connecta::Scope::Denied, :not_found unless Connecta::Scope::Projection.marked?(conversation.inbox_id)

    connecta_scope_verify_token!(attachment, conversation)
    raise Connecta::Scope::Denied, :not_found unless Connecta::Scope::Gate.new(current_user).read?(
      conversation, access_path: 'attachment_download'
    )

    connecta_scope_serve!(attachment)
  end

  private

  # Verificação coesa do token (attachment/blob/usuário/conta/epoch/expiração; Gate fica no show):
  # extração artificial piora clareza sem reduzir acoplamento real.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def connecta_scope_verify_token!(attachment, conversation)
    payload = Connecta::Scope::AttachmentToken.read(params[:token].to_s)
    epoch_row = Connecta::Scope::UserAuthEpoch.find_by(user_id: current_user.id)
    valid = payload.is_a?(Hash) && !epoch_row.nil? && epoch_row.revoked_locally_at.nil? &&
            payload['attachment_id'] == attachment.id &&
            payload['blob_id'] == attachment.file.blob.id &&
            payload['user_id'] == current_user.id &&
            payload['account_id'] == Current.account.id &&
            payload['epoch'] == epoch_row.epoch
    return if valid

    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: conversation.id, surface: 'attachment',
                                         access_path: 'attachment_download', decision: 'deny')
    raise Connecta::Scope::Denied, :not_found
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def connecta_scope_serve!(attachment)
    if params[:thumb].present?
      variant = attachment.file.representation(resize_to_fill: [250, nil]).processed
      send_data variant.download, filename: attachment.file.filename.to_s, type: variant.content_type, disposition: :inline
    else
      blob = attachment.file.blob
      send_data blob.download, filename: blob.filename.to_s, type: blob.content_type, disposition: :inline
    end
  end
end
