class Connecta::Runtime::Installer
  def self.install!
    return unless Connecta::Runtime::Feature.enabled?
    return if @installed

    # Sem as tabelas (banco novo, antes da migração) o adapter não instala e o restante dos hooks
    # também não deve rodar: alguns fazem consultas ao banco no boot.
    return unless Connecta::Runtime::G0Adapter.install!

    # Keep the G0 test-only entrypoint untouched; production installs the same hooks through this explicit opt-in bridge.
    Connecta::Scope::Installer.install_policies_and_finders!
    Connecta::Scope::Installer.install_conversations!
    Connecta::Scope::Installer.install_notifications_and_mentions!
    Connecta::Scope::Installer.install_contacts!
    Connecta::Scope::Installer.install_inboxes_and_captain!
    Connecta::Scope::Installer.install_attachments!
    Connecta::Scope::Installer.install_realtime!
    Connecta::Scope::Installer.install_denied_rendering!

    unless Whatsapp::IncomingMessageBaileysService <= Connecta::Transfer::IncomingHook
      Whatsapp::IncomingMessageBaileysService.prepend(Connecta::Transfer::IncomingHook)
    end
    Message.prepend(Connecta::Transfer::OutboundDispatch::MessageHook) unless Message <= Connecta::Transfer::OutboundDispatch::MessageHook
    SendReplyJob.prepend(Connecta::Transfer::SendReplyHook) unless SendReplyJob <= Connecta::Transfer::SendReplyHook
    Conversation.after_create { Connecta::Runtime::ReceptionScopeCreator.call(self) }
    Connecta::Runtime::ReceptionScopeCreator.verify_marked_inboxes!
    @installed = true
  end
end
