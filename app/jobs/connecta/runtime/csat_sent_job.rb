# Avisa o WP de que a pesquisa foi enviada (criada e despachada) na conversa.
# Contrato v1 (implementado no WP pelo Coder paralelo — usar exatamente este):
# `POST /attendance/v1/csat/sent` com `{account_id, conversation_id:
# <display_id>, case_protocol, survey_uuid (uuid da conversa), contact_id
# (contato do Chatwoot), mode ("link"|"whatsapp"), sent_at ISO8601}`.
# Sem telefone/nome. Idempotente por `conversation_id` + `survey_uuid`
# (o WP deduplica; reenvios do retry carregam os mesmos valores).
class Connecta::Runtime::CsatSentJob < ApplicationJob
  queue_as :default
  retry_on Connecta::Runtime::PlatformClient::Error, wait: 10.seconds, attempts: 24

  def perform(message_id)
    message = Message.find(message_id)
    conversation = message.conversation
    protocol = Connecta::Scope::CsatPolicy.protocol_for(conversation)
    return if protocol.blank?

    account_id = Connecta::Runtime::Feature.current_account_id!
    Connecta::Runtime::PlatformClient.new.post(
      '/attendance/v1/csat/sent',
      account_id: account_id,
      conversation_id: conversation.display_id,
      case_protocol: protocol,
      survey_uuid: conversation.uuid,
      contact_id: conversation.contact_id,
      mode: Connecta::Scope::CsatPolicy.survey_mode(conversation.inbox),
      sent_at: message.created_at.iso8601
    )
  rescue ArgumentError => e
    raise Connecta::Runtime::PlatformClient::Error.new(e.message, status: :service_unavailable)
  end
end
