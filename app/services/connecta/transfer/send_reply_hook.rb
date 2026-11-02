# Prepend em SendReplyJob (T0.7b): mensagem de inbox marcada só chega ao conector depois do claim atômico; as demais seguem o job nativo.
# Timeout e 409 "já em processamento" são ambíguos (o provedor pode ter enviado) e viram uncertain; outro erro vira failed.
# Os dois só são gravados: o claim não age sobre linha fora de queued, então a re-execução do job não reenvia.
module Connecta::Transfer::SendReplyHook
  def perform(message_id)
    message = Message.find(message_id)
    return super unless Connecta::Transfer::OutboundDispatch.dispatchable?(message)

    Connecta::Transfer::OutboundDispatch.enqueue!(message)
    unless Connecta::Transfer::OutboundDispatch.claim!(message)
      Connecta::Transfer::OutboundDispatch.mark_parked_visible!(message)
      return
    end

    begin
      super
    rescue Timeout::Error, Whatsapp::Providers::WhatsappBaileysService::MessageAlreadyProcessingError
      Connecta::Transfer::OutboundDispatch.resolve!(message, 'uncertain')
      raise
    rescue StandardError
      Connecta::Transfer::OutboundDispatch.resolve!(message, 'failed')
      raise
    else
      Connecta::Transfer::OutboundDispatch.resolve!(message, message.reload.failed? ? 'failed' : 'accepted')
    end
  end
end
