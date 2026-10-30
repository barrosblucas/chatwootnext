# URLs de anexo de conversa marcada apontam à rota autorizada do spike (T0.2-c3). Inbox não marcada segue nativa.
# Emite token por usuário (Current.user) com epoch atual; sem usuário autenticado no contexto, segue nativo
# (jobs/serviços externos e mailers ficam com o comportamento nativo — limite documentado na evidência 20).
# A rota de download existe só quando o Installer a desenhou (specs G0); sem ela, segue nativo.
module Connecta::Scope::AttachmentUrlHook
  def file_url
    return super unless file.attached?

    connecta_scope_authorized_url || super
  end

  def thumb_url
    return super unless file.attached? && image?

    connecta_scope_authorized_url(thumb: true) || super
  end

  # Serviços externos usam download_url em jobs (sem Current.user: segue nativo). Em serialização autenticada
  # de conversa marcada, aponta à rota autorizada em vez da URL curta do serviço.
  def download_url
    return super unless file.attached?

    connecta_scope_authorized_url || super
  end

  private

  # Áudio serializa inline_audio_url (redirect permanente); marcada + autenticada vai à rota autorizada.
  def inline_audio_url
    return super unless file.attached?

    connecta_scope_authorized_url || super
  end

  # Monta a URL autorizada guardando nativo (sem usuário/sem rota/não marcada/erro): verificação coesa;
  # extração artificial piora clareza sem reduzir acoplamento real.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def connecta_scope_authorized_url(thumb: false)
    user = Current.user
    return nil if user.nil?
    return nil unless Rails.application.routes.url_helpers.respond_to?(:connecta_scope_attachment_download_url)

    conversation = message&.conversation
    return nil if conversation.nil?
    return nil unless Connecta::Scope::Projection.marked?(conversation.inbox_id)

    epoch_row = Connecta::Scope::UserAuthEpoch.find_by(user_id: user.id)
    token = Connecta::Scope::AttachmentToken.issue(attachment: self, user: user, account: account,
                                                   epoch: epoch_row&.epoch || 0)
    args = { account_id: account.id, attachment_id: id, token: token }
    args[:thumb] = 1 if thumb
    Rails.application.routes.url_helpers.connecta_scope_attachment_download_url(**args)
  rescue StandardError
    nil
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
