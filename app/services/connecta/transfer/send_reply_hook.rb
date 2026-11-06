# Prepend em SendReplyJob (T0.7b): mensagem de inbox marcada só chega ao conector depois do claim atômico; as demais seguem o job nativo.
# Timeout é ambíguo (o provedor pode ter enviado) e vira uncertain; outro erro vira failed. 409 "já em processamento" não é ambíguo
# para nós: outro worker detém o lock do mesmo message id e o provedor deduplica o reenvio, então a linha volta a queued e o retry
# nativo (SendReplyJob, 60s) tenta de novo. O claim não age sobre linha fora de queued: re-execuções não reenviam.
module Connecta::Transfer::SendReplyHook
  def perform(message_id)
    message = Message.find(message_id)
    return super unless Connecta::Transfer::OutboundDispatch.managed?(message)

    reconcile_accepted!(message)
    return if message.source_id.present?

    Connecta::Transfer::OutboundDispatch.enqueue!(message)
    unless Connecta::Transfer::OutboundDispatch.claim!(message)
      # Só o claim derrotado por estado parked (sem setor/transferência) é falha visível.
      # dispatching = outro worker está enviando; accepted/failed/uncertain = resultado já decidido.
      # Marcar failed aqui transformaria um envio concorrente legítimo em erro para o agente.
      record = Connecta::Transfer::OutboundDispatchRecord.find_by(message_id: message.id)
      Connecta::Transfer::OutboundDispatch.mark_parked_visible!(message) if record&.state == 'parked'
      return
    end

    begin
      super
    rescue Timeout::Error
      Connecta::Transfer::OutboundDispatch.resolve!(message, 'uncertain')
      raise
    rescue Whatsapp::Providers::WhatsappBaileysService::MessageAlreadyProcessingError
      # Devolve ao estado claimável para o retry nativo do SendReplyJob (wait 60s) tentar
      # novamente quando o worker que detém o lock terminar. O id do provedor é o mesmo
      # e deduplica o envio caso a outra tentativa já tenha saído.
      Connecta::Transfer::OutboundDispatchRecord.find_by(message_id: message.id)&.update!(state: 'queued')
      raise
    rescue StandardError
      Connecta::Transfer::OutboundDispatch.resolve!(message, 'failed')
      raise
    else
      Connecta::Transfer::OutboundDispatch.resolve!(message, message.reload.failed? ? 'failed' : 'accepted')
    end
  end

  # O retry de um 409 pode encontrar a mensagem já enviada pelo worker que detinha
  # o lock (source_id preenchido). Sem esta reconciliação a linha ficaria queued
  # para sempre e uma transferência ficaria esperando um envio que já terminou.
  def reconcile_accepted!(message)
    return if message.source_id.blank?

    record = Connecta::Transfer::OutboundDispatchRecord.find_by(message_id: message.id)
    return unless record && %w[queued dispatching uncertain].include?(record.state)

    record.update!(state: 'accepted', connector_message_id: message.source_id)
  end
end
