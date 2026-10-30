# Contexto transitório de autorização para jobs de entrega G0.
# Keep capture and revalidation branches together so serialized context shapes stay auditable.
# rubocop:disable Metrics/ModuleLength
module Connecta::Scope::DeliveryContext
  KEY = :connecta_scope_delivery_context
  MAILER = 'AgentNotifications::ConversationNotificationsMailer'.freeze

  module_function

  def with(context, target)
    previous = ActiveSupport::IsolatedExecutionState[KEY]
    ActiveSupport::IsolatedExecutionState[KEY] = { 'target' => target, 'ctx' => context }
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[KEY] = previous
  end

  def take(target)
    entry = ActiveSupport::IsolatedExecutionState[KEY]
    return unless entry.is_a?(Hash) && entry['target'] == target && !entry['taken']

    ActiveSupport::IsolatedExecutionState[KEY] = entry.merge('taken' => true)
    entry['ctx']
  end

  def epoch_of(user_id)
    Connecta::Scope::UserAuthEpoch.find_by(user_id: user_id)&.epoch
  end

  def epoch_current?(user_id, epoch)
    epoch.is_a?(Integer) && Connecta::Scope::UserAuthEpoch.exists?(user_id: user_id, epoch: epoch, revoked_locally_at: nil)
  end

  def epoch_same?(user_id, epoch)
    epoch.nil? ? !Connecta::Scope::UserAuthEpoch.exists?(user_id: user_id) : epoch_current?(user_id, epoch)
  end

  def notification_conversation(notification)
    notification.primary_actor if notification.primary_actor_type == Conversation.name
  end

  def for_notification(notification)
    return unless notification.is_a?(Notification)

    conversation = notification_conversation(notification)
    return unless conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)

    {
      'v' => 1, 'kind' => 'notification', 'account_id' => notification.account_id,
      'conversation_id' => conversation.id, 'notification_id' => notification.id,
      'user_id' => notification.user_id, 'epoch' => epoch_of(notification.user_id)
    }
  end

  # The branch order distinguishes notification and conversation context before native fallback.
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def for_socket(account, tokens, event_name, data)
    notification = ActiveSupport::IsolatedExecutionState[Connecta::Scope::SocketHook::NOTIFICATION_KEY]
    if notification && notification_event?(event_name)
      context = for_notification(notification)
      return context if context
    end

    conversation = ActiveSupport::IsolatedExecutionState[Connecta::Scope::SocketHook::CONVERSATION_KEY]
    return conversation_context(account, tokens, conversation) if conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)

    context = special_socket_context(account, tokens, event_name, data)
    return context if context

    inbox_id = conversation&.inbox_id || Connecta::Scope::DeliveryCheck.payload_inbox_id(data)
    { 'v' => 1, 'kind' => 'native', 'account_id' => account.id, 'inbox_id' => inbox_id,
      'contact_id' => conversation&.contact_id }
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  private_class_method def special_socket_context(account, tokens, event_name, data)
    return notification_context(account, tokens, event_name, data) if notification_event?(event_name)
    return contact_context(account, tokens, event_name, data) if Connecta::Scope::SocketHook::CONTACT_EVENTS.include?(event_name)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def notification_deliverable?(context, notification)
    return false unless context.is_a?(Hash) && context['v'] == 1 && context['kind'] == 'notification'
    return false unless context['account_id'] == notification.account_id && context['notification_id'] == notification.id
    return false unless context['user_id'] == notification.user_id && epoch_current?(context['user_id'], context['epoch'])

    conversation = notification_conversation(notification)
    return false unless conversation && conversation.id == context['conversation_id'] && Connecta::Scope::Projection.marked?(conversation.inbox_id)

    account = notification.account
    user = account.users.find_by(id: context['user_id'])
    return false unless user && !Connecta::Scope::Projection.new(user).admin?

    Connecta::Scope::Gate.new(user).notifiable?(conversation)
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/AbcSize
  private_class_method def conversation_context(account, tokens, conversation)
    token_list = Array(tokens)
    users = account.users.where(pubsub_token: token_list).to_a
    native_admin_ids = native_same_account_ids(users, account, conversation)
    users = users.reject { |user| native_admin_ids.include?(user.id) || Connecta::Scope::Projection.new(user).admin? }
    # A conversa liga-se ao contact_inbox por conversations.contact_inbox_id (schema.rb); contact_inboxes não tem conversation_id.
    widget_ids = ::ContactInbox.where(id: conversation.contact_inbox_id).filter_map do |contact_inbox|
      contact_inbox.id if token_list.include?(contact_inbox.pubsub_token)
    end
    {
      'v' => 1, 'kind' => 'conversation_and_native_admin', 'account_id' => account.id, 'conversation_id' => conversation.id,
      'users' => users.map { |user| [user.id, epoch_of(user.id)] }, 'contact_inbox_ids' => widget_ids,
      'native_admins' => native_admin_ids.map { |user_id| [user_id, epoch_of(user_id)] }
    }
  end
  # rubocop:enable Metrics/AbcSize

  # I.2: full same-account — só nativo da CONTA DO RECURSO entra no canal de
  # conteúdo, recarregado pelo `NativeAdmin.authorized_for?` (conversa viva); cross-account nunca libera.
  private_class_method def native_same_account_ids(users, account, conversation)
    users.select do |user|
      Connecta::Scope::NativeAdmin.administrator?(user, account) && Connecta::Scope::NativeAdmin.authorized_for?(user, conversation)
    end.map(&:id)
  end

  private_class_method def notification_context(account, tokens, _event_name, data)
    notification_data = data[:notification] || data['notification'] || {}
    id = notification_data[:id] || notification_data['id']
    notification = Notification.find_by(id: id, account_id: account.id)
    return unless notification && Array(tokens).include?(notification.user&.pubsub_token)

    for_notification(notification)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  private_class_method def contact_context(account, tokens, event_name, data)
    contact_data = data[:contact_data] || data['contact_data'] || data[:contact] || data['contact'] || data
    contact_id = contact_data[:id] || contact_data['id']
    state = ActiveSupport::IsolatedExecutionState[Connecta::Scope::ContactLifecycleHook::CONTACT_DELIVERY_KEY]
    snapshot = state.is_a?(Hash) ? state[contact_id] || state[contact_id.to_s] : nil

    if event_name == Events::Types::CONTACT_DELETED
      if snapshot && snapshot['account_id'] == account.id
        state.delete(contact_id)
        state.delete(contact_id.to_s)
        return { 'v' => 1, 'kind' => 'native', 'account_id' => account.id, 'contact_id' => contact_id } unless snapshot['marked']

        return {
          'v' => 1, 'kind' => 'contact_deleted', 'account_id' => account.id, 'contact_id' => contact_id,
          'users' => snapshot['users'] || [], 'scope_ids' => snapshot['scope_ids'] || []
        }
      end

      return { 'v' => 1, 'kind' => 'contact_ambiguous', 'account_id' => account.id, 'contact_id' => contact_id } if marked_account?(account)

      return { 'v' => 1, 'kind' => 'native', 'account_id' => account.id, 'contact_id' => contact_id }
    end

    contact = ::Contact.find_by(id: contact_id, account_id: account.id)
    unless contact && Connecta::Scope::ContactVisibility.linked?(contact)
      return { 'v' => 1, 'kind' => 'native', 'account_id' => account.id,
               'contact_id' => contact_id }
    end

    users = account.users.where(pubsub_token: Array(tokens)).reject do |user|
      account.administrators.exists?(id: user.id) || Connecta::Scope::Projection.new(user).admin?
    end
    { 'v' => 1, 'kind' => 'contact', 'account_id' => account.id, 'contact_id' => contact_id,
      'users' => users.map { |user| [user.id, epoch_of(user.id)] } }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  private_class_method def marked_account?(account)
    Connecta::Scope::ScopedInbox.account_marked?(account.id)
  end

  private_class_method def notification_event?(event_name)
    %w[notification.created notification.updated notification.deleted].include?(event_name.to_s)
  end
end
# rubocop:enable Metrics/ModuleLength
