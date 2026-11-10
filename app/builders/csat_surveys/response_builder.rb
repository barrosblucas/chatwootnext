class CsatSurveys::ResponseBuilder
  pattr_initialize [:message]

  def perform
    raise 'Invalid Message' unless message.input_csat?

    conversation = message.conversation
    rating = message.content_attributes.dig('submitted_values', 'csat_survey_response', 'rating')
    feedback_message = message.content_attributes.dig('submitted_values', 'csat_survey_response', 'feedback_message')

    return if rating.blank?

    process_csat_response(conversation, rating, feedback_message)
  end

  private

  def process_csat_response(conversation, rating, feedback_message)
    # Com `disable_feedback` na inbox, o comentário é ignorado (não persiste).
    feedback_message = nil if Connecta::Scope::CsatPolicy.feedback_disabled?(conversation.inbox)

    csat_survey_response = message.csat_survey_response || CsatSurveyResponse.new(
      message_id: message.id, account_id: message.account_id, conversation_id: message.conversation_id,
      contact_id: conversation.contact_id, assigned_agent: conversation.assignee
    )
    csat_survey_response.rating = rating
    csat_survey_response.feedback_message = feedback_message
    csat_survey_response.save!
    enqueue_connecta_push(conversation, csat_survey_response)
    csat_survey_response
  end

  # Pesquisa de conversa escopada com protocolo é espelhada no WP (job com
  # retry; sem dados de contato, sem comentário; idempotente por resposta).
  def enqueue_connecta_push(conversation, csat_survey_response)
    return unless Connecta::Scope::CsatPolicy.scoped_inbox?(conversation.inbox_id)
    return unless Connecta::Scope::CsatPolicy.final_protocol_resolution?(conversation)

    Connecta::Runtime::CsatPushJob.perform_later(csat_survey_response.id)
  end
end
