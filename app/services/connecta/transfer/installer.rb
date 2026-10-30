# Liga os hooks do spike G0 (T0.3 corte, T0.7b despacho). Só os specs de transferência chamam install!; fora deles o fluxo nativo permanece.
module Connecta::Transfer::Installer
  def self.install!
    return unless Rails.env.test?

    Whatsapp::IncomingMessageBaileysService.prepend(Connecta::Transfer::IncomingHook)
    Message.prepend(Connecta::Transfer::OutboundDispatch::MessageHook)
    SendReplyJob.prepend(Connecta::Transfer::SendReplyHook)
  end
end
