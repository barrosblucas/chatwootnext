# Prepend nos 4 controllers de redirect/proxy de blobs e representations do ActiveStorage (instalado só pelo spike G0).
# Blob anexado a conversa de inbox marcada: link legado nega com 404 — inclusive URL emitida antes da proteção,
# pois a checagem lê o vínculo vivo no banco, não a data de emissão. Blob compartilhado com inbox marcada também
# nega (fail-closed: qualquer vínculo marcado contamina). Sem vínculo marcado (inbox não marcada, logo, macro,
# anexos de sistema): segue nativo. Disk/direct_uploads ficam nativos (URLs curtas de serviço; decisão pendente, evidência 20).
module Connecta::Scope::ActiveStorageGuard
  def show
    if connecta_scope_marked_blob?(@blob)
      head :not_found
    else
      super
    end
  end

  private

  # Roda no próprio set_representation, antes do `.processed` da variante — variante inválida/ausente
  # em thumb marcado virava 500 em vez do 404 do contrato. Só os controllers de representations chamam
  # este callback (before_action nativo); nos de blobs é método morto inofensivo. Assinatura inválida
  # mantém o nativo (`head :not_found` igual ao original).
  def set_representation
    blob = blob_scope.find_signed(params[:signed_blob_id] || params[:signed_id])
    if connecta_scope_marked_blob?(blob)
      head :not_found
    else
      @blob = blob
      super
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
  end

  def connecta_scope_marked_blob?(blob)
    return false if blob.nil?

    record_ids = blob.attachments.where(record_type: 'Attachment').pluck(:record_id)
    return false if record_ids.empty?

    marked_ids = Connecta::Scope::Projection.marked_inbox_ids
    return false if marked_ids.empty?

    ::Attachment.joins(message: :conversation).exists?(
      id: record_ids, conversations: { inbox_id: marked_ids }
    )
  rescue StandardError
    false
  end
end

# Representations: este callback nativo (before_action) não existe nos controllers de blobs, então
# este módulo nunca é prepended neles — só nos dois de representations. Nega marcado antes do `.processed`.
module Connecta::Scope::RepresentationsGuard
  include Connecta::Scope::ActiveStorageGuard

  private

  def set_representation
    blob = blob_scope.find_signed(params[:signed_blob_id] || params[:signed_id])
    if connecta_scope_marked_blob?(blob)
      head :not_found
    else
      @blob = blob
      super
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
  end
end
