# Prepend em Conversations::UnreadCounts::Counter (instalado só pelo spike G0).
# O cache nativo soma a inbox inteira e não respeita grants. Inbox marcada sai dele e é contada só pelas conversas visíveis ao usuário,
# com o mesmo critério de não lidas e de modo de permissão do contador nativo. Admin nominal não recebe contagem de inbox marcada.
module Connecta::Scope::UnreadCountHook
  private

  def visible_inbox_ids
    super - Connecta::Scope::Projection.marked_inbox_ids
  end

  def unread_inbox_counts
    merge_scoped(super, scoped_rows.pluck(:inbox_id))
  end

  def unread_label_counts
    merge_scoped(super, scoped_rows.flat_map { |row| row[:label_ids] })
  end

  def unread_team_counts
    merge_scoped(super, scoped_rows.filter_map { |row| row[:team_id] if visible_team_ids.include?(row[:team_id]) })
  end

  def merge_scoped(native_counts, ids)
    native_counts.merge(ids.map(&:to_s).tally) { |_id, native_count, scoped_count| native_count + scoped_count }
  end

  def scoped_rows
    @scoped_rows ||= scoped_unread_conversations.pluck(:id, :inbox_id, :team_id, :cached_label_list).map do |_id, inbox_id, team_id, label_list|
      { inbox_id: inbox_id, team_id: team_id, label_ids: scoped_label_ids(label_list) }
    end
  end

  def scoped_unread_conversations
    Connecta::Scope::ConversationQuery.new(permission_filtered(unread_in_member_marked_inboxes), user).perform
  end

  def unread_in_member_marked_inboxes
    account.conversations.open
           .joins(:messages)
           .merge(Message.incoming.reorder(nil))
           .where(messages: { account_id: account.id })
           .where(unread_since_last_seen_condition)
           .where(inbox_id: member_marked_inbox_ids)
           .distinct
  end

  def permission_filtered(relation)
    case permission_mode
    when :unassigned_and_mine then relation.where(assignee_id: [nil, user.id])
    when :mine then relation.where(assignee_id: user.id)
    else relation
    end
  end

  # Espelha Conversations::UnreadCounts::Builder#unread_conversations, que grava o mesmo critério no cache nativo.
  def unread_since_last_seen_condition
    conversations = Conversation.arel_table
    messages = Message.arel_table

    conversations[:agent_last_seen_at].eq(nil).or(messages[:created_at].gt(conversations[:agent_last_seen_at]))
  end

  def member_marked_inbox_ids
    user.inboxes.where(account_id: account.id, id: Connecta::Scope::Projection.marked_inbox_ids).select(:id)
  end

  def scoped_label_ids(label_list)
    titles = label_list.to_s.split(',').map(&:strip).compact_blank
    labels_by_title.values_at(*titles).compact & sidebar_label_ids
  end

  def labels_by_title
    @labels_by_title ||= account.labels.pluck(:title, :id).to_h
  end
end
