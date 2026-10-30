# Prepend em ActionCableListener (instalado só pelo spike G0). Em conversa de inbox marcada, eventos de conversa, mensagem e digitação
# vão só para inbox members que o Gate lê, INCLUINDO nativo full same-account (I.2). Nominal recebe só metadados, sem conteúdo.
# Contato vinculado a inbox marcada sai do stream `account_<id>`: vai só a quem o ContactVisibility permite. Demais seguem o nativo.
# Roteamento coeso de eventos para escopo/snapshot/admin (Gate + snapshot pre-destroy + metadados de admin):
# fatiar o módulo espalharia roteamento/guards de segurança sem reduzir acoplamento real.
# rubocop:disable Metrics/ModuleLength
module Connecta::Scope::SocketHook
  # Estado por execução: o singleton do listener é compartilhado entre threads, então a conversa do evento não pode ficar em ivar.
  CONVERSATION_KEY = :connecta_scope_socket_conversation
  NOTIFICATION_KEY = :connecta_scope_socket_notification

  # Evento => campo que leva à conversa. Presença e notificações ficam fora (ver evidência 09); contatos são tratados em `broadcast`.
  CONVERSATION_EVENTS = {
    message_created: :message, message_updated: :message, first_reply_created: :message, conversation_created: :conversation,
    conversation_read: :conversation, conversation_status_changed: :conversation, conversation_updated: :conversation,
    assignee_changed: :conversation, team_changed: :conversation, conversation_contact_changed: :conversation,
    conversation_typing_on: :conversation, conversation_typing_off: :conversation, conversation_recording: :conversation,
    scheduled_message_created: :scheduled_message, scheduled_message_updated: :scheduled_message,
    scheduled_message_deleted: :scheduled_message, recurring_scheduled_message_created: :recurring_scheduled_message,
    recurring_scheduled_message_updated: :recurring_scheduled_message, recurring_scheduled_message_deleted: :recurring_scheduled_message
  }.freeze

  # Admin recebe metadados só destes eventos (campos em `admin_metadata`). Os demais não chegam a admin.
  ADMIN_MESSAGE_EVENTS = [Events::Types::MESSAGE_CREATED, Events::Types::MESSAGE_UPDATED, Events::Types::FIRST_REPLY_CREATED].freeze
  ADMIN_CONVERSATION_EVENTS = [
    Events::Types::CONVERSATION_CREATED, Events::Types::CONVERSATION_READ, Events::Types::CONVERSATION_STATUS_CHANGED,
    Events::Types::CONVERSATION_UPDATED, Events::Types::ASSIGNEE_CHANGED, Events::Types::TEAM_CHANGED,
    Events::Types::CONVERSATION_CONTACT_CHANGED
  ].freeze
  ADMIN_EVENTS = (ADMIN_MESSAGE_EVENTS + ADMIN_CONVERSATION_EVENTS).freeze

  # Eventos de contato que o listener envia ao stream `account_<id>`. Com contato vinculado, o `broadcast` troca esse stream.
  CONTACT_EVENTS = [
    Events::Types::CONTACT_CREATED, Events::Types::CONTACT_UPDATED, Events::Types::CONTACT_MERGED,
    Events::Types::CONTACT_DELETED, Events::Types::CONTACT_GROUP_SYNCED
  ].freeze

  CONVERSATION_EVENTS.each do |event_name, subject|
    define_method(event_name) { |event| with_socket_conversation(event.data[subject]) { super(event) } }
  end

  # Menção vai direto ao token do mencionado (sem user_tokens), então o filtro roda antes do listener.
  # Nominal fica fora (sem conteúdo). NATIVO same-account full (I.2) PODE ser mencionado:
  # o Gate o libera (`socket_reader?`) e a menção direta usa o token dele.
  # Agents/grants setoriais continuam limitados pelo mesmo filtro.
  def conversation_mentioned(event)
    conversation = event.data[:conversation]
    return super unless Connecta::Scope::Projection.marked?(conversation.inbox_id)
    return unless socket_reader?(event.data[:user], conversation)

    with_socket_conversation(conversation) { super(event) }
  end

  def notification_created(event)
    with_socket_notification(event.data[:notification]) { super(event) }
  end

  def notification_updated(event)
    with_socket_notification(event.data[:notification]) { super(event) }
  end

  # Conversa apagada chega só com conversation_data. Sem registro, o Gate não tem o que checar: inbox marcada não envia o sinal.
  def conversation_unread_count_changed(event)
    return with_socket_conversation(event.data[:conversation]) { super(event) } if event.data[:conversation]

    deleted = event.data[:conversation_data]&.with_indifferent_access
    super unless deleted && Connecta::Scope::Projection.marked?(deleted[:inbox_id])
  end

  private

  def user_tokens(account, agents)
    conversation = ActiveSupport::IsolatedExecutionState[CONVERSATION_KEY]

    return super unless conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)

    own = agents.select { |user| socket_reader?(user, conversation) }.map(&:pubsub_token).uniq
    own | native_tokens_for_account(account, conversation)
  end

  # Administrador NATIVO same-account full (I.2) recebe conteúdo completo realtime
  # (entra no job normal do ActionCableBroadcastJob com revalidação de vínculo no job).
  # Nominal segue só por metadados (job próprio `AdminMetadataBroadcastJob`).
  # Nativo NÃO precisa ser membro da inbox: `agents` recebido do listener nativo
  # exclui administrators, então o lookup é direto por AccountUser da conta.
  def native_tokens_for_account(account, conversation)
    return [] unless conversation.account_id == account.id

    candidates = account.users.where(id: account.account_users.where(role: :administrator).select(:user_id))
    allowed = candidates.select do |user|
      Connecta::Scope::NativeAdmin.authorized_for?(user, conversation) &&
        Connecta::Scope::Gate.new(user).read?(conversation, access_path: 'socket_native_admin')
    end
    allowed.map(&:pubsub_token).uniq
  end

  # Nativo ATUAL same-account prevalece sobre grant nominal (precedência Gate/HTTP):
  # NativeAdmin autoriza primeiro; nominal-only segue fora do socket normal (só metadados).
  # Sem bypass: Gate central decide com auditoria nos dois ramos; epoch/conta/roles valem dentro dele.
  def socket_reader?(user, conversation)
    if Connecta::Scope::NativeAdmin.authorized_for?(user, conversation)
      return Connecta::Scope::Gate.new(user).read?(conversation, access_path: 'socket')
    end
    return false if Connecta::Scope::Projection.new(user).admin?

    Connecta::Scope::Gate.new(user).read?(conversation, access_path: 'socket')
  end

  # Tokens de agente seguem o broadcast nativo. Nominais vão por job próprio com metadados, porque o job nativo relê a conversa inteira.
  # Nativo full (I.2) entra no job NORMAL com conteúdo, revalidado no `DeliveryCheck` (vínculo atual + epoch + conta).
  # Contato vinculado a inbox marcada troca o stream da conta pelos tokens de quem o ContactVisibility permite ver.
  # `contact.deleted` usa o snapshot pré-destroy (ContactLifecycleHook): o vínculo pode já ter sumido e o contato apagado
  # não passa no `visible_scope`, então os destinatários capturados antes do destroy valem; sem snapshot, segue o vínculo vivo.
  def broadcast(account, tokens, event_name, data, include_performer: true)
    tokens = contact_scoped_tokens(account, tokens, event_name, data)
    context = Connecta::Scope::DeliveryContext.for_socket(account, tokens, event_name, data)
    projected = Connecta::Scope::ContactDataProjection.socket_payload(
      data, force_contact: context.is_a?(Hash) && context['kind'] == 'contact_deleted'
    )
    Connecta::Scope::DeliveryContext.with(context, ActionCableBroadcastJob.name) do
      super(account, tokens, event_name, projected, include_performer: include_performer)
    end
    conversation = ActiveSupport::IsolatedExecutionState[CONVERSATION_KEY]
    return unless conversation && ADMIN_EVENTS.include?(event_name) && Connecta::Scope::Projection.marked?(conversation.inbox_id)

    payload = admin_metadata(conversation, event_name, data).merge(account_id: account.id)
    enqueue_admin_metadata(account, event_name, payload)
  end

  # `contact.deleted` usa o snapshot pré-destroy e os destinatários capturados nele valem; sem snapshot, segue o vínculo vivo.
  def contact_scoped_tokens(account, tokens, event_name, data)
    return tokens unless CONTACT_EVENTS.include?(event_name)

    contact_id = data[:id] || data['id']
    snapshot = contact_destroy_snapshot(account, contact_id)
    if event_name == Events::Types::CONTACT_DELETED && snapshot
      consume_contact_destroy_snapshot!
      return snapshot[:tokens]
    end
    return contact_reader_tokens(account, contact_id) if socket_contact_linked?(contact_id)

    tokens
  end

  def admin_metadata(conversation, event_name, data)
    return { id: data[:id], conversation_id: conversation.display_id } if ADMIN_MESSAGE_EVENTS.include?(event_name)

    { id: conversation.display_id, inbox_id: conversation.inbox_id, status: conversation.status,
      org_unit_id: Connecta::Scope::ConversationScope.find_by(conversation_id: conversation.id)&.org_unit_id }
  end

  # Admins: nominais da projeção (grant admin_nominal, válido só com sessão verificada) e
  # NATIVOS same-account (full, com conteúdo pelo job normal). Metadata vai só a nominal.
  def socket_admin_tokens(account)
    socket_admins(account).select { |_user, role| role == 'nominal' }.map { |user, _role| user.pubsub_token }.uniq
  end

  def socket_admins(account)
    nominal = account.users.where(id: Connecta::Scope::UserGrant.where(permission: 'admin_nominal').select(:user_id))
    allowed = nominal.select do |user|
      Connecta::Scope::Projection.new(user).admin? && !Connecta::Scope::NativeAdmin.administrator?(user, account)
    end
    allowed.map { |user| [user, 'nominal'] }.uniq { |user, _role| user.id }
  end

  # Full same-account (I.2): nativo NÃO entra no canal admin_metadata.
  def enqueue_admin_metadata(account, event_name, payload)
    admins = socket_admins(account)
    nominal_only = admins.select { |_user, role| role == 'nominal' }
    tokens = nominal_only.map { |user, _role| user.pubsub_token }.uniq
    return if tokens.empty?

    context = {
      'v' => 1, 'kind' => 'admin_metadata', 'account_id' => account.id,
      'admins' => nominal_only.map { |user, role| [user.id, role, Connecta::Scope::DeliveryContext.epoch_of(user.id)] }
    }
    Connecta::Scope::DeliveryContext.with(context, Connecta::Scope::AdminMetadataBroadcastJob.name) do
      Connecta::Scope::AdminMetadataBroadcastJob.perform_later(tokens, event_name, payload)
    end
  end

  def socket_contact_linked?(contact_id)
    ::ContactInbox.exists?(contact_id: contact_id, inbox_id: Connecta::Scope::Projection.marked_inbox_ids)
  end

  # Snapshot pré-destroy: vale só para a conta e o contato do evento; sem vínculo marcado na captura, segue o vínculo vivo.
  # Snapshot com vínculo marcado nunca segue nativo: consumo garante que contact.deleted não cai no stream da conta.
  # Contato: nativo fica de fora do canal (vínculo não dá full sem conversa); nativo recebe conversa/mensagem/evento.
  def contact_destroy_snapshot(account, contact_id)
    snapshot = ActiveSupport::IsolatedExecutionState[Connecta::Scope::ContactLifecycleHook::CONTACT_SNAPSHOT_KEY]
    return unless snapshot.is_a?(Hash) && snapshot[:contact_id] == contact_id && snapshot[:account_id] == account.id

    snapshot
  end

  def consume_contact_destroy_snapshot!
    ActiveSupport::IsolatedExecutionState[Connecta::Scope::ContactLifecycleHook::CONTACT_SNAPSHOT_KEY] = nil
  end

  # Candidatos são os membros das inboxes marcadas do contato; passa quem o ContactVisibility permite ver.
  # Contato vinculado: nativo fica de fora (sem conteúdo neste canal; nativo recebe conversa/mensagem/evento).
  def contact_reader_tokens(account, contact_id)
    inbox_ids = ::ContactInbox.where(contact_id: contact_id, inbox_id: Connecta::Scope::Projection.marked_inbox_ids).select(:inbox_id)
    members = account.users.where(id: ::InboxMember.where(inbox_id: inbox_ids).select(:user_id))

    members.select { |user| socket_contact_reader?(account, user, contact_id) }.map(&:pubsub_token)
  end

  # Admin nominal fica de fora antes da consulta: a listagem dele grava auditoria (ConversationQuery#admin_listing).
  # Contato: nativo fica de fora (sem conteúdo neste canal; nativo recebe conversa/mensagem/evento).
  def socket_contact_reader?(account, user, contact_id)
    return false if account.administrators.exists?(id: user.id) || Connecta::Scope::Projection.new(user).admin?

    Connecta::Scope::ContactVisibility.visible_scope(account, user).exists?(contact_id)
  end

  def with_socket_conversation(record)
    previous = ActiveSupport::IsolatedExecutionState[CONVERSATION_KEY]
    ActiveSupport::IsolatedExecutionState[CONVERSATION_KEY] = record.is_a?(Conversation) ? record : record.conversation
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[CONVERSATION_KEY] = previous
  end

  def with_socket_notification(notification)
    conversation = Connecta::Scope::DeliveryContext.notification_conversation(notification)
    return yield unless conversation && Connecta::Scope::Projection.marked?(conversation.inbox_id)
    return unless Connecta::Scope::Gate.new(notification.user).notifiable?(conversation)

    previous = ActiveSupport::IsolatedExecutionState[NOTIFICATION_KEY]
    ActiveSupport::IsolatedExecutionState[NOTIFICATION_KEY] = notification
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[NOTIFICATION_KEY] = previous if defined?(previous)
  end
end
# rubocop:enable Metrics/ModuleLength
