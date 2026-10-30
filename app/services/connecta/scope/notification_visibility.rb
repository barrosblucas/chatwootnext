# Filtra conversas marcadas antes de paginação, contagem e contagem não lida.
module Connecta::Scope::NotificationVisibility
  module_function

  def filter(relation, user, account)
    marked_ids = Connecta::Scope::Projection.marked_inbox_ids
    return relation if marked_ids.empty?

    marked_conversations = account.conversations.where(inbox_id: marked_ids)
    marked_notification_ids = Notification.where(primary_actor_type: Conversation.name,
                                                 primary_actor_id: marked_conversations.select(:id)).select(:id)
    return relation.where.not(id: marked_notification_ids) if Connecta::Scope::Projection.new(user).admin?

    visible_ids = Connecta::Scope::ConversationQuery.new(marked_conversations, user).perform.select(:id)
    hidden_ids = Notification.where(id: marked_notification_ids)
                             .where.not(primary_actor_id: visible_ids).select(:id)
    relation.where.not(id: hidden_ids)
  end
end
