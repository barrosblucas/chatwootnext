class Public::Api::V1::CsatSurveyController < PublicController
  before_action :set_conversation
  before_action :set_message

  def show; end

  def update
    render json: { error: 'You cannot update the CSAT survey after 14 days' }, status: :unprocessable_entity and return if check_csat_locked

    @message.update!(filtered_message_params)
  end

  private

  def set_conversation
    return if params[:id].blank?

    @conversation = Conversation.find_by!(uuid: params[:id])
  end

  def set_message
    @message = @conversation.messages.find_by!(content_type: 'input_csat')
  end

  def message_update_params
    params.permit(message: [{ submitted_values: [:name, :title, :value, { csat_survey_response: [:feedback_message, :rating] }] }])
  end

  # Com `disable_feedback` na inbox, o comentário vindo da página pública é
  # descartado aqui também (o ResponseBuilder ignora de todo jeito).
  def filtered_message_params
    permitted = message_update_params[:message]
    return permitted unless Connecta::Scope::CsatPolicy.feedback_disabled?(@conversation.inbox)

    strip_submitted_feedback!(permitted)
    permitted
  end

  def strip_submitted_feedback!(node)
    node = node.first if node.is_a?(Array)
    return unless node.respond_to?(:[])

    submitted = node[:submitted_values] || node['submitted_values']
    submitted = submitted.first if submitted.is_a?(Array)
    return unless submitted.respond_to?(:[])

    response = submitted[:csat_survey_response] || submitted['csat_survey_response']
    response.delete(:feedback_message) if response.respond_to?(:delete)
  end

  def check_csat_locked
    (Time.zone.now.to_date - @message.created_at.to_date).to_i > 14
  end
end
