# Revalidação dos destinatários serializados de jobs G0.
# Keep the explicit kind matrix together; each branch independently fails closed.
# rubocop:disable Metrics/ModuleLength
module Connecta::Scope::DeliveryCheck
  module_function

  # rubocop:disable Metrics/CyclomaticComplexity
  def allowed_tokens(context, tokens, event_name, data)
    return legacy_allowed?(tokens, event_name, data) unless context.is_a?(Hash)
    return [] unless context['v'] == 1

    case context['kind']
    when 'conversation' then conversation_tokens(context)
    when 'native_admin', 'conversation_and_native_admin' then conversation_and_native_admin_tokens(context)
    when 'notification' then notification_tokens(context)
    when 'contact' then contact_tokens(context)
    when 'contact_deleted' then deleted_contact_tokens(context)
    when 'contact_ambiguous', 'admin_metadata' then []
    when 'native', 'unbound'
      native_allowed?(context, data, event_name) ? Array(tokens) : []
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # Legacy payloads lack the enqueue-time identity needed for per-recipient revalidation.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def legacy_allowed?(tokens, event_name, data)
    account_id = data[:account_id] || data['account_id']
    account = Account.find_by(id: account_id)
    return false if account.nil? && Connecta::Scope::ScopedInbox.exists?

    event = event_name.to_s
    if event.start_with?('notification.')
      notification_data = data[:notification] || data['notification'] || {}
      notification_id = notification_data[:id] || notification_data['id']
      notification = Notification.find_by(id: notification_id, account_id: account_id)
      conversation = notification&.primary_actor
      return false if conversation.is_a?(Conversation) && Connecta::Scope::Projection.marked?(conversation.inbox_id)
    end

    if event.start_with?('contact.')
      contact_id = data[:id] || data['id']
      return false if account && marked_account?(account)
      return false if contact_id && Connecta::Scope::ContactVisibility.linked?(::Contact.new(id: contact_id))
    end

    inbox_id = data[:inbox_id] || data['inbox_id']
    inbox_id ||= payload_inbox_id(data)
    conversation_id = data[:conversation_id] || data['conversation_id']
    conversation_id ||= data.dig(:conversation, :id) if data[:conversation].is_a?(Hash)
    conversation = Conversation.find_by(id: conversation_id, account_id: account_id) if conversation_id
    conversation = account.conversations.find_by(display_id: data[:id]) if conversation.nil? && account && data[:id]
    inbox_id ||= conversation&.inbox_id
    return false if inbox_id && Connecta::Scope::Projection.marked?(inbox_id)

    Array(tokens)
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def notification_deliverable?(context, notification)
    Connecta::Scope::DeliveryContext.notification_deliverable?(context, notification)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  private_class_method def conversation_tokens(context)
    account = Account.find_by(id: context['account_id'])
    conversation = account&.conversations&.find_by(id: context['conversation_id'])
    return [] unless account && conversation

    user_tokens = Array(context['users']).filter_map do |user_id, epoch|
      user = account.users.find_by(id: user_id)
      next unless user && Connecta::Scope::DeliveryContext.epoch_same?(user.id, epoch) && !Connecta::Scope::Projection.new(user).admin?
      next if account.administrators.exists?(id: user.id)
      next unless Connecta::Scope::Gate.new(user).read?(conversation, access_path: 'socket_job')

      user.pubsub_token
    end
    # A conversa liga-se ao contact_inbox por conversations.contact_inbox_id (schema.rb); contact_inboxes não tem conversation_id.
    widget_tokens = ::ContactInbox.where(
      id: [conversation.contact_inbox_id] & Array(context['contact_inbox_ids']),
      contact_id: conversation.contact_id, inbox_id: conversation.inbox_id
    ).filter_map(&:pubsub_token)
    user_tokens + widget_tokens
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Administrador nativo full same-account (I.2): conteúdo realtime da conta,
  # revalidando vínculo atual + epoch no momento da entrega; cross-account nunca
  # libera (conta do contexto vs. conta da conversa). Auditoria pelo Gate (read?).
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  private_class_method def conversation_and_native_admin_tokens(context)
    account = Account.find_by(id: context['account_id'])
    conversation = account&.conversations&.find_by(id: context['conversation_id'])
    return [] unless account && conversation && conversation.account_id == account.id

    user_tokens = Array(context['users']).filter_map do |user_id, epoch|
      user = account.users.find_by(id: user_id)
      next unless user && Connecta::Scope::DeliveryContext.epoch_same?(user.id, epoch) && !Connecta::Scope::Projection.new(user).admin?
      next if account.administrators.exists?(id: user.id)
      next unless Connecta::Scope::Gate.new(user).read?(conversation, access_path: 'socket_job')

      user.pubsub_token
    end
    widget_tokens = ::ContactInbox.where(
      id: [conversation.contact_inbox_id] & Array(context['contact_inbox_ids']),
      contact_id: conversation.contact_id, inbox_id: conversation.inbox_id
    ).filter_map(&:pubsub_token)
    native_tokens = Array(context['native_admins']).filter_map do |user_id, epoch|
      native_job_token(account, conversation, user_id, epoch)
    end
    user_tokens + widget_tokens + native_tokens
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Revalidação do nativo no momento da entrega: vínculo atual + epoch + conta do recurso; audita via Gate.
  private_class_method def native_job_token(account, conversation, user_id, epoch)
    user = account.users.find_by(id: user_id)
    return unless user && Connecta::Scope::DeliveryContext.epoch_same?(user.id, epoch)
    return unless Connecta::Scope::NativeAdmin.administrator?(user, account)
    return unless Connecta::Scope::Gate.new(user).read?(conversation, access_path: 'socket_job_native_admin')

    user.pubsub_token
  end
  private_class_method def notification_tokens(context)
    account = Account.find_by(id: context['account_id'])
    notification = account&.notifications&.find_by(id: context['notification_id'])
    return [] unless notification && notification_deliverable?(context, notification)

    [notification.user.pubsub_token]
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  # `conversation` + `conversation_and_native_admin` usam o mesmo contexto de contato:
  # o canal de contato NÃO inclui nativo (ContactVisibility); o nativo administra
  # pelo conteúdo de conversa/mensagem/evento, não pelo canal de contato.
  private_class_method def contact_tokens(context)
    account = Account.find_by(id: context['account_id'])
    contact = account&.contacts&.find_by(id: context['contact_id'])
    return [] unless account && contact && Connecta::Scope::ContactVisibility.linked?(contact)

    Array(context['users']).filter_map do |user_id, epoch|
      user = account.users.find_by(id: user_id)
      next unless user && Connecta::Scope::DeliveryContext.epoch_same?(user.id, epoch) && !Connecta::Scope::Projection.new(user).admin?
      next unless Connecta::Scope::ContactVisibility.visible_scope(account, user).exists?(contact.id)

      user.pubsub_token
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  private_class_method def deleted_contact_tokens(context)
    account = Account.find_by(id: context['account_id'])
    return [] unless account

    Array(context['users']).filter_map do |user_id, epoch|
      user = account.users.find_by(id: user_id)
      next unless user && Connecta::Scope::DeliveryContext.epoch_same?(user.id, epoch) && !Connecta::Scope::Projection.new(user).admin?
      next unless Array(context['scope_ids']).any? do |scope_id|
        scope = Connecta::Scope::ConversationScope.find_by(id: scope_id, contact_id: context['contact_id'])
        scope && Connecta::Scope::Gate.new(user).readable_scope?(scope)
      end

      user.pubsub_token
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  private_class_method def native_allowed?(context, data, event_name)
    if context['kind'] == 'unbound'
      inbox_id = payload_inbox_id(data)
      return !inbox_id || !Connecta::Scope::Projection.marked?(inbox_id)
    end

    return false unless Account.exists?(id: context['account_id'])

    inbox_id = context['inbox_id'] || payload_inbox_id(data)
    return false if inbox_id && Connecta::Scope::Projection.marked?(inbox_id)

    contact_id = context['contact_id']
    contact_id ||= data[:id] || data['id'] if event_name.to_s.start_with?('contact.')
    return false if contact_id && Connecta::Scope::ContactVisibility.linked?(::Contact.new(id: contact_id))

    true
  end

  def payload_inbox_id(data)
    payload = data.with_indifferent_access
    payload[:inbox_id] || payload.dig(:conversation, :inbox_id) || payload.dig(:notification, :primary_actor, :inbox_id)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  private_class_method def marked_account?(account)
    Connecta::Scope::ScopedInbox.account_marked?(account.id)
  end
end
# rubocop:enable Metrics/ModuleLength
