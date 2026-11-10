# Espelha a resposta do CSAT de conversa escopada no WP (Fase 2).
# Contrato v1 (implementado no WP pelo Coder paralelo — usar exatamente este):
# `POST /attendance/v1/csat` com `{account_id, conversation_id: <display_id>,
# case_protocol, rating 1..5, responded_at ISO8601, csat_response_id}`.
# Sem dados de contato, sem comentário. Idempotente por `csat_response_id`
# (o WP deduplica; reenvios do retry carregam o mesmo id).
class Connecta::Runtime::CsatPushJob < ApplicationJob
  queue_as :default
  retry_on Connecta::Runtime::PlatformClient::Error, wait: 10.seconds, attempts: 24

  def perform(csat_response_id)
    response = CsatSurveyResponse.find(csat_response_id)
    conversation = response.conversation
    protocol = Connecta::Scope::CsatPolicy.protocol_for(conversation)
    return if protocol.blank?

    account_id = Connecta::Runtime::Feature.current_account_id!
    Connecta::Runtime::PlatformClient.new.post(
      '/attendance/v1/csat',
      account_id: account_id,
      conversation_id: conversation.display_id,
      case_protocol: protocol,
      rating: response.rating,
      responded_at: response.updated_at.iso8601,
      csat_response_id: response.id
    )
  rescue ArgumentError => e
    raise Connecta::Runtime::PlatformClient::Error.new(e.message, status: :service_unavailable)
  end
end
