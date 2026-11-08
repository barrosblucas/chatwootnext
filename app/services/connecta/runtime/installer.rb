class Connecta::Runtime::Installer
  # Callback por símbolo (não proc) para o teste remover de forma determinística
  # sem resetar os demais callbacks nativos de Conversation.
  module ReceptionCallback
    def connecta_reception_after_create
      Connecta::Runtime::ReceptionScopeCreator.call(self) if Connecta::Runtime::Feature.enabled?
    end
  end
  RECEPTION_CALLBACK = :connecta_reception_after_create

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
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
    # O callback é instalado uma vez por processo; a checagem em tempo de execução
    # impede que ele continue agindo em specs/hosts que desligaram o recurso depois
    # do boot (o ENV é lido de novo a cada conversa criada).
    Conversation.include(ReceptionCallback) unless Conversation <= ReceptionCallback
    Conversation.after_create(RECEPTION_CALLBACK) unless
      Conversation._create_callbacks.any? { |callback| callback.filter == RECEPTION_CALLBACK }
    # Fail-open no boot: numa conta fresca a primeira inbox marcada ainda não existe quando
    # este verify roda (o enforce vem depois, via upsert oficial), então a unidade de
    # recepção ausente não pode travar o boot — só registra o evento com a contagem.
    # O fail-closed continua em ReceptionScopeCreator.call (conversa nova sem unidade).
    begin
      Connecta::Runtime::ReceptionScopeCreator.verify_marked_inboxes!
    rescue Connecta::Runtime::ReceptionScopeCreator::MissingReceptionUnit
      Rails.logger.error(
        "connecta_reception_unit_missing marked_inbox_count=#{Connecta::Scope::ScopedInbox.where(enforcement: 'enforce').count}"
      )
    end
    @installed = true
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # Só para specs: remove o callback de criação que o installer global deixou
  # no processo, sem tocar nos demais callbacks nativos de Conversation.
  def self.uninstall_reception_callback!
    return unless Conversation._create_callbacks.any? { |callback| callback.filter == RECEPTION_CALLBACK }

    Conversation.skip_callback(:create, :after, RECEPTION_CALLBACK)
  end
end
