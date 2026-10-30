# Ações em notificações ocultas respondem 404 antes de alterar o registro.
module Connecta::Scope::NotificationsControllerHook
  private

  def fetch_notification
    super
    visible = Connecta::Scope::NotificationVisibility.filter(
      Notification.where(id: @notification.id), current_user, Current.account
    )
    raise ActiveRecord::RecordNotFound unless visible.exists?
  end
end
