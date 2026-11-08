class Api::V1::Accounts::Connecta::ConversationMetadataController < Api::V1::Accounts::BaseController
  # Metadados de identificação para a lista. O cliente informa display_ids; a
  # resposta contém somente os que a ConversationQuery deixar visíveis. IDs
  # ausentes/ocultos são omitidos (não há 403/404 por linha, para não permitir
  # enumeração). Limite fixo evita consultas sem tamanho.
  def index
    ids = parsed_ids
    return render json: { error: 'invalid_ids' }, status: :unprocessable_entity if ids.nil?
    return render json: { conversations: {} } if ids.empty?

    visible = Connecta::Scope::ConversationQuery
              .new(Current.account.conversations.where(display_id: ids), current_user)
              .perform
              .to_a
    metadata = Connecta::Scope::ConversationMetadata.for_conversations(visible)
    payload = visible.each_with_object({}) do |conversation, result|
      item = metadata[conversation.id]
      result[conversation.display_id] = item if item
    end
    render json: { conversations: payload }
  end

  private

  def parsed_ids
    raw = params[:ids]
    values = raw.is_a?(Array) ? raw.flat_map { |value| value.to_s.split(',') } : raw.to_s.split(',')
    values = values.map(&:strip).reject(&:empty?)
    return [] if values.empty?

    ids = values.map do |value|
      Integer(value, 10)
    rescue ArgumentError, TypeError
      nil
    end
    return nil if ids.any?(&:nil?) || ids.any? { |id| id <= 0 }
    return nil if ids.uniq.length > Connecta::Scope::ConversationMetadata::MAX_IDS

    ids.uniq
  end
end
