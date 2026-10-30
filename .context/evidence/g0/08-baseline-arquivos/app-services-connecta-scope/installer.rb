# Liga os hooks do spike G0. Só os specs G0 chamam install!; fora deles os hooks não são prepended e o código nativo permanece.
module Connecta::Scope::Installer
  def self.install!
    return unless Rails.env.test?

    ConversationPolicy.prepend(Connecta::Scope::PolicyHook)
    Conversations::PermissionFilterService.prepend(Connecta::Scope::FinderHook)
    [Api::V1::Accounts::ConversationsController, Api::V1::Accounts::Conversations::BaseController].each do |controller|
      controller.prepend(Connecta::Scope::ConversationHttpHook)
      controller.rescue_from(Connecta::Scope::Denied, with: :connecta_scope_denied)
      controller.before_action(:connecta_scope_write_guard!)
    end
    Api::V1::Accounts::ConversationsController.prepend_before_action(:connecta_scope_create_guard!, only: :create)
    Api::V1::Accounts::Conversations::ConnectaTransfersController.before_action(:connecta_scope_transfer_guard!)
  end
end
