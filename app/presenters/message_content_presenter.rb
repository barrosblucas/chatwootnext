class MessageContentPresenter < SimpleDelegator
  def outgoing_content
    Messages::MarkdownRendererService.new(
      content_with_survey_link,
      conversation.inbox.channel_type,
      conversation.inbox.channel
    ).render
  end

  def webhook_content
    Messages::WebhookContentNormalizer.normalize(content_with_survey_link)
  end

  private

  def content_with_survey_link
    if should_append_survey_link?
      survey_link = survey_url(conversation.uuid)
      connecta_message = connecta_survey_message(survey_link)
      return connecta_message if connecta_message.present?

      custom_message = inbox.csat_config&.dig('message')
      custom_message.present? ? "#{custom_message} #{survey_link}" : I18n.t('conversations.survey.response', link: survey_link)
    else
      content
    end
  end

  # Conversa escopada com protocolo usa o texto do protocolo (config com
  # `{{protocolo}}` ou padrão pt-BR); demais casos seguem o nativo (nil).
  # No modo whatsapp o cidadão responde na conversa: sem link.
  def connecta_survey_message(survey_link)
    return nil unless Connecta::Scope::CsatPolicy.scoped_inbox?(conversation.inbox_id)
    return nil if Connecta::Scope::CsatPolicy.protocol_for(conversation).blank?

    base = Connecta::Scope::CsatPolicy.survey_message(conversation)
    return base if Connecta::Scope::CsatPolicy.whatsapp_mode?(conversation.inbox)

    "#{base} #{survey_link}"
  end

  def should_append_survey_link?
    input_csat? && !inbox.web_widget?
  end

  def survey_url(conversation_uuid)
    "#{ENV.fetch('FRONTEND_URL', nil)}/survey/responses/#{conversation_uuid}"
  end
end
