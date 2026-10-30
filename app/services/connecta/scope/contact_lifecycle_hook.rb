# Snapshot pré-destroy de contato vinculado a inbox marcada (spike G0, T0.2-c6b).
# `Contact` usa `destroy_async` em `contact_inboxes` e despacha `contact.deleted` em `after_destroy_commit`
# (`app/models/contact.rb:62,74,257-265`) pelo dispatcher síncrono (`app/dispatchers/sync_dispatcher.rb:2-5`).
# Quando o `SocketHook` roda, o vínculo pode já ter sumido: `socket_contact_linked?` retorna falso e o evento
# cairia no stream `account_<id>` com nome/telefone/e-mail do contato marcado (evidência 09 §8.4 item 1).
# E mesmo com o vínculo vivo, `visible_scope` não acha o contato apagado, então ninguém receberia o sinal.
# Este hook captura ANTES do destroy os destinatários autorizados (tokens de quem o ContactVisibility permite)
# em `IsolatedExecutionState`; o `SocketHook` consome o snapshot no broadcast de `contact.deleted`.
# Snapshot só interno (ids + tokens, sem payload/segredo novo); instalado só via `Installer` (`Rails.env.test?`).
# `destroy!` passa por `destroy`, então um override cobre `ContactsController#destroy`, `BulkDeleteService` e `ContactMergeAction`.
module Connecta::Scope::ContactLifecycleHook
  CONTACT_SNAPSHOT_KEY = :connecta_scope_contact_destroy_snapshot
  CONTACT_DELIVERY_KEY = :connecta_scope_contact_delivery

  def destroy
    capture_contact_destroy_snapshot
    super
  ensure
    ActiveSupport::IsolatedExecutionState[CONTACT_SNAPSHOT_KEY] = nil unless destroyed?
    clear_contact_delivery_snapshot unless destroyed?
  end

  private

  # Guarda { contact_id:, account_id:, tokens: }; contato sem vínculo marcado não guarda nada (nativo intacto).
  # Só ids e tokens: nenhum nome/telefone/e-mail no snapshot. Sem rescue: falha alto, sem fallback aberto.
  # rubocop:disable Metrics/AbcSize
  def capture_contact_destroy_snapshot
    marked_ids = ::ContactInbox.where(contact_id: id, inbox_id: Connecta::Scope::Projection.marked_inbox_ids).pluck(:inbox_id)
    if marked_ids.empty?
      ActiveSupport::IsolatedExecutionState[CONTACT_SNAPSHOT_KEY] = nil
      store_contact_delivery('marked' => false)
      return
    end

    account = ::Account.find_by(id: account_id)
    if account.blank?
      store_contact_delivery('marked' => true, 'users' => [], 'scope_ids' => [])
      return
    end

    members = account.users.where(id: ::InboxMember.where(inbox_id: marked_ids).select(:user_id))
    readers = members.select { |user| snapshot_contact_reader?(account, user) }
    tokens = readers.map(&:pubsub_token)
    ActiveSupport::IsolatedExecutionState[CONTACT_SNAPSHOT_KEY] = { contact_id: id, account_id: account_id, tokens: tokens }
    store_contact_delivery(
      'marked' => true, 'users' => readers.map { |user| [user.id, Connecta::Scope::DeliveryContext.epoch_of(user.id)] },
      'scope_ids' => Connecta::Scope::ConversationScope.where(contact_id: id, inbox_id: marked_ids).ids
    )
  end
  # rubocop:enable Metrics/AbcSize

  def store_contact_delivery(entry)
    state = ActiveSupport::IsolatedExecutionState[CONTACT_DELIVERY_KEY] || {}
    ActiveSupport::IsolatedExecutionState[CONTACT_DELIVERY_KEY] = state.merge(id => entry.merge('account_id' => account_id))
  end

  def clear_contact_delivery_snapshot
    state = ActiveSupport::IsolatedExecutionState[CONTACT_DELIVERY_KEY]
    return unless state.is_a?(Hash)

    state.delete(id)
    state.delete(id.to_s)
  end

  # Mesmo critério do SocketHook: admin (nominal ou nativo) fica de fora antes da consulta, que gravaria auditoria.
  def snapshot_contact_reader?(account, user)
    return false if account.administrators.exists?(id: user.id) || Connecta::Scope::Projection.new(user).admin?

    Connecta::Scope::ContactVisibility.visible_scope(account, user).exists?(id)
  end
end
