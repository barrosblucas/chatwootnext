# Aplica o escopo antes que o finder paginate ou conte notificações.
module Connecta::Scope::NotificationFinderHook
  private

  def set_up
    super
    @notifications = Connecta::Scope::NotificationVisibility.filter(@notifications, current_user, current_account)
  end
end
