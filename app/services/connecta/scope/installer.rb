# Liga os hooks do spike G0. Só os specs G0 chamam install!; fora deles os hooks não são prepended e o código nativo permanece.
# Bootstrap coeso e idempotente dos hooks (registros por área + rota de download desenhada uma vez):
# fatiar o módulo espalharia install!/guards de segurança e pioraria a clareza sem reduzir acoplamento real.
# rubocop:disable Metrics/ModuleLength
module Connecta::Scope::Installer
  def self.install!
    return unless Rails.env.test?

    install_policies_and_finders!
    install_conversations!
    install_notifications_and_mentions!
    install_contacts!
    install_inboxes_and_captain!
    install_attachments!
    install_realtime!
    install_denied_rendering!
  end

  def self.install_policies_and_finders!
    ConversationPolicy.prepend(Connecta::Scope::PolicyHook)
    Conversations::PermissionFilterService.prepend(Connecta::Scope::FinderHook)
    ConversationFinder.prepend(Connecta::Scope::ConversationFinderHook)
    Conversations::UnreadCounts::Counter.prepend(Connecta::Scope::UnreadCountHook)
    SearchService.prepend(Connecta::Scope::SearchHook)
    Contacts::FilterService.prepend(Connecta::Scope::ContactFilterServiceHook)
  end

  def self.install_notifications_and_mentions!
    NotificationBuilder.prepend(Connecta::Scope::NotificationHook)
    Messages::MentionService.prepend(Connecta::Scope::MentionHook)
    NotificationFinder.prepend(Connecta::Scope::NotificationFinderHook)
    Api::V1::Accounts::NotificationsController.prepend(Connecta::Scope::NotificationsControllerHook)
  end

  def self.install_conversations!
    [Api::V1::Accounts::ConversationsController, Api::V1::Accounts::Conversations::BaseController].each do |controller|
      controller.prepend(Connecta::Scope::ConversationHttpHook)
      controller.before_action(:connecta_scope_write_guard!)
    end
    # Ciclo de vida da resolução (decisão 005): reabertura automática nativa
    # nunca reabre conversa resolvida de inbox marcada; mudança de status
    # resolved↔open move o escopo closed↔active via after_update_commit.
    ::Message.prepend(Connecta::Scope::ConversationResolution::MessageHook) unless
      ::Message <= Connecta::Scope::ConversationResolution::MessageHook
    install_resolution_hook!
    # Reuso "abrir existente" no ConversationBuilder (micro passo 1b): roda
    # depois dos before_actions nativos (conta/inbox/contact/contact_inbox
    # resolvidos e inbox show? autorizada) e antes do create/after_create.
    ConversationBuilder.prepend(Connecta::Scope::ConversationReuse::BuilderInterceptor) unless
      ConversationBuilder <= Connecta::Scope::ConversationReuse::BuilderInterceptor
    Api::V1::Accounts::ConversationsController.before_action(:connecta_scope_transcript_guard!, only: :transcript)
    Api::V1::Accounts::Conversations::ConnectaTransfersController.before_action(:connecta_scope_transfer_guard!)
    # Reuso "abrir existente" fora do teste G0: o opt-in de produção (runtime)
    # instala os mesmos hooks do spike, incluindo o interceptor do builder.
    ConversationBuilder.prepend(Connecta::Scope::ConversationReuse::BuilderInterceptor) unless
      ConversationBuilder <= Connecta::Scope::ConversationReuse::BuilderInterceptor
    Api::V1::Accounts::Conversations::DirectUploadsController.prepend(Connecta::Scope::DirectUploadsHook)
    Api::V1::Accounts::Conversations::MessagesController.prepend(Connecta::Scope::FollowUpDedupeHook)
    Api::V1::Accounts::BulkActionsController.prepend(Connecta::Scope::BulkHook)
    Api::V1::Accounts::BulkActionsController.before_action(:connecta_scope_bulk_guard!, only: :create)
    Api::V1::Accounts::ConversationsController.prepend(Connecta::Scope::PresenceBulkHook)
    Api::V1::Accounts::ConversationsController.before_action(:connecta_scope_presence_bulk_guard!, only: :presence_subscribe_bulk)
  end

  def self.install_contacts!
    ::Contact.prepend(Connecta::Scope::ContactLifecycleHook)
    ::Contact.prepend(Connecta::Scope::ContactPushProjectionHook)
    Api::V1::Accounts::ContactsController.prepend(Connecta::Scope::ContactHook)
    Api::V1::Accounts::ContactsController.before_action(:connecta_scope_export_guard!, only: :export)
    Api::V1::Accounts::Contacts::BaseController.prepend(Connecta::Scope::ContactSubresourceHook)
    Api::V1::Accounts::Contacts::NotesController.prepend(Connecta::Scope::ContactNotesHook)
  end

  def self.install_inboxes_and_captain!
    Api::V1::Accounts::InboxesController.prepend(Connecta::Scope::InboxHook)
    Api::V1::Accounts::InboxesController.prepend_before_action(:connecta_scope_inbox_create_guard!, only: :create)
    Api::V1::Accounts::InboxMembersController.prepend(Connecta::Scope::InboxMembersHook)
    Api::V1::Accounts::Captain::TasksController.prepend(Connecta::Scope::CaptainTasksHook)
    Api::V1::Accounts::Captain::TasksController.before_action(:connecta_scope_captain_guard!)
    # O guard do Copilot usa Current.account: roda como before_action comum (depois do current_account herdado),
    # nunca prepend (antes dele Current.account é nil e o lookup vira 500 em vez de 404/criação).
    Api::V1::Accounts::Captain::CopilotThreadsController.prepend(Connecta::Scope::CopilotHook)
    Api::V1::Accounts::Captain::CopilotThreadsController.before_action(:connecta_scope_copilot_guard!, only: :create)
    Api::V1::Accounts::Captain::CopilotMessagesController.prepend(Connecta::Scope::CopilotHook)
    Api::V1::Accounts::Captain::CopilotMessagesController.before_action(:connecta_scope_copilot_guard!, only: :create)
    Api::V1::Accounts::Captain::AgentSessionsController.prepend(Connecta::Scope::CaptainHttpHook)
    Api::V1::Accounts::Captain::MessageReportsController.prepend(Connecta::Scope::CaptainHttpHook)
    Captain::Copilot::ChatService.prepend(Connecta::Scope::CopilotChatHook)
    [
      Captain::Tools::Copilot::GetConversationService, Captain::Tools::Copilot::SearchConversationsService,
      Captain::Tools::Copilot::GetContactService, Captain::Tools::Copilot::SearchContactsService
    ].each { |tool| tool.prepend(Connecta::Scope::CopilotToolHook) }
  end

  def self.install_realtime!
    ActionCableListener.prepend(Connecta::Scope::SocketHook)
    ActionCableBroadcastJob.prepend(Connecta::Scope::DeliveryBinding)
    ActionCableBroadcastJob.prepend(Connecta::Scope::BroadcastJobGuard)
    [Notification::PushNotificationJob, Notification::EmailNotificationJob].each do |job|
      job.prepend(Connecta::Scope::DeliveryBinding)
      job.prepend(Connecta::Scope::NotificationDeliveryGuard)
    end
    Notification::EmailNotificationService.prepend(Connecta::Scope::EmailDeliveryHook)
    AgentNotifications::ConversationNotificationsMailer.include(Connecta::Scope::MailDeliveryGuard)
    AgentNotifications::ConversationNotificationsMailer.before_deliver(:connecta_scope_mail_guard!)
    Connecta::Scope::AdminMetadataBroadcastJob.prepend(Connecta::Scope::DeliveryBinding)
    Connecta::Scope::AdminMetadataBroadcastJob.prepend(Connecta::Scope::AdminMetadataDeliveryGuard)
  end

  # Anexos de conversa marcada (T0.2-c3): serialização aponta à rota autorizada, links legados negam com 404,
  # download autorizado revalida sessão/conta/epoch/Gate. Rota desenhada em runtime (sem editar routes.rb/core);
  # instalação só roda em Rails.env.test? (guard no install!). Inbox não marcada segue nativa em todos os pontos.
  def self.install_attachments!
    Attachment.prepend(Connecta::Scope::AttachmentUrlHook)
    [
      ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController
    ].each { |controller| controller.prepend(Connecta::Scope::ActiveStorageGuard) }
    [
      ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController
    ].each { |controller| controller.prepend(Connecta::Scope::RepresentationsGuard) }
    connecta_scope_draw_download_route!
    install_denied_rendering_for!(Connecta::Scope::AttachmentDownloadsController)
  end

  def self.connecta_scope_draw_download_route!
    return if @connecta_scope_download_route_drawn

    Rails.application.routes.append do
      get '/api/v1/accounts/:account_id/connecta_attachments/:attachment_id/download',
          to: 'connecta/scope/attachment_downloads#show', as: :connecta_scope_attachment_download
    end
    # `append` só entra em vigor no próximo finalize: sem reload a rota nova responde 404 e o helper
    # segue inexistente (o hook recai no nativo). Recarrega uma vez para ativar rota+helper.
    Rails.application.reload_routes!
    @connecta_scope_download_route_drawn = true
  rescue StandardError
    @connecta_scope_download_route_drawn = false
    raise
  end

  # Negação autenticada vira 404 (leitura) ou 403 (escrita). O bloco roda no contexto do controller, então `render` funciona.
  def self.install_denied_rendering_for!(controller)
    controller.rescue_from(Connecta::Scope::Denied) { |error| render json: { error: error.message }, status: error.status }
  end

  def self.install_resolution_hook!
    return if @connecta_resolution_hook_installed

    Conversation.prepend(Connecta::Scope::ConversationResolution::ConversationHook) unless
      Conversation <= Connecta::Scope::ConversationResolution::ConversationHook
    Conversation.after_update_commit(:connecta_resolution_after_status_change)
    @connecta_resolution_hook_installed = true
  end

  def self.install_denied_rendering!
    [
      Api::V1::Accounts::ConversationsController, Api::V1::Accounts::Conversations::BaseController, Api::V1::Accounts::ContactsController,
      Api::V1::Accounts::Contacts::BaseController, Api::V1::Accounts::BulkActionsController, Api::V1::Accounts::InboxesController,
      Api::V1::Accounts::InboxMembersController, Api::V1::Accounts::Captain::TasksController,
      Api::V1::Accounts::Captain::CopilotThreadsController, Api::V1::Accounts::Captain::CopilotMessagesController,
      Api::V1::Accounts::Captain::AgentSessionsController, Api::V1::Accounts::Captain::MessageReportsController,
      Api::V1::Accounts::Conversations::DirectUploadsController,
      Api::V1::Accounts::Conversations::ConnectaManualAdmissionsController
    ].each { |controller| install_denied_rendering_for!(controller) }
  end
end
# rubocop:enable Metrics/ModuleLength
