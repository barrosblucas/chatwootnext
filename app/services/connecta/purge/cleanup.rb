require 'digest'
require 'json'

# Limpeza interna de atendimentos sintéticos/operacionais de uma lista EXPLÍCITA
# de contas. Não é rota HTTP, não tem permissão nova e não é chamada pelo runtime:
# o wrapper privado do operador (rails runner) é o único ponto de entrada.
#
# Contrato:
# - plan(account_ids:) => plano com hash SHA256 e contagens; sem PII.
# - apply(account_ids:, expected_hash:, confirmation:, writers_stopped:)
#   revalida o hash ANTES de deletar; a transação cobre mensagens, conversas e
#   escopos; o purge dos blobs só roda DEPOIS do commit.
# - purge_blobs(blob_ids:) => retry exato dos blobs pendentes, sem tocar no banco
#   de conversas.
class Connecta::Purge::Cleanup
  class Blocked < StandardError; end

  PROTECTED_TABLES = %w[
    accounts users account_users inboxes inbox_members contacts contact_inboxes
    agent_bots agent_bot_inboxes teams labels webhooks channel_whatsapp
    connecta_scoped_inboxes connecta_user_grants connecta_user_auth_epochs
    connecta_acl_sync_state
  ].freeze
  AUDIT_TABLES = %w[audits connecta_access_audits].freeze
  PROTECTED_DEPENDENT_MODELS = %w[Account User Inbox Contact ContactInbox AgentBot Team Label Webhook].freeze
  MAX_ACCOUNTS = 50
  HASH_PATTERN = /\A[0-9a-f]{64}\z/
  TABLE_PATTERN = /\A[a-z0-9_]+\z/

  class << self
    def plan(account_ids:, protected_tables: PROTECTED_TABLES, audit_tables: AUDIT_TABLES)
      new(
        account_ids: account_ids, protected_tables: protected_tables, audit_tables: audit_tables
      ).plan
    end

    def apply(account_ids:, expected_hash:, confirmation:, writers_stopped:, # rubocop:disable Metrics/ParameterLists
              protected_tables: PROTECTED_TABLES, audit_tables: AUDIT_TABLES)
      new(
        account_ids: account_ids, protected_tables: protected_tables, audit_tables: audit_tables
      ).apply(expected_hash: expected_hash, confirmation: confirmation, writers_stopped: writers_stopped)
    end

    def purge_blobs(blob_ids:)
      new(account_ids: nil, skip_account_validation: true).purge_blobs(blob_ids: blob_ids)
    end
  end

  def initialize(account_ids:, protected_tables: PROTECTED_TABLES, audit_tables: AUDIT_TABLES,
                 skip_account_validation: false)
    @account_ids = skip_account_validation ? [] : normalize_account_ids(account_ids)
    @protected_tables = normalize_tables(protected_tables, 'PROTECTED_TABLE_INVALID')
    @audit_tables = normalize_tables(audit_tables, 'AUDIT_TABLE_INVALID')
    ensure_protected_dependencies! unless skip_account_validation
  end

  def plan
    data = inventory
    {
      status: 'inspected',
      inventory_hash: data[:hash],
      counts: data[:counts],
      protected_counts: data[:protected_counts],
      audit_counts: data[:audit_counts],
      dependencies: data[:dependencies],
      destroy_callbacks: data[:destroy_callbacks],
      payload: data[:payload]
    }
  end

  def apply(expected_hash:, confirmation:, writers_stopped:) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    fail!('WRITERS_NOT_STOPPED') unless writers_stopped == true
    valid_confirmation = expected_hash.to_s.match?(HASH_PATTERN) && confirmation.to_s == "APPLY:#{expected_hash}"
    fail!('CONFIRMATION_REQUIRED') unless valid_confirmation

    current = inventory
    fail!('INVENTORY_CHANGED') unless current[:hash] == expected_hash.to_s

    payload = current[:payload]
    before_protected = current[:protected_counts]
    before_audit = current[:audit_counts]

    ActiveRecord::Base.transaction do
      detach_active_storage_rows!(payload)
      Message.where(id: payload[:message_ids]).find_each(&:destroy!)
      Conversation.where(id: payload[:conversation_ids]).find_each(&:destroy!)
      Connecta::Scope::ConversationScope.where(conversation_id: payload[:scope_ids]).delete_all

      verify_targets_gone!(payload, before_protected, before_audit)
    end

    blob_result = purge_blobs(blob_ids: payload[:blob_ids])
    {
      status: blob_result[:status] == 'committed' ? 'committed' : 'committed_blob_pending',
      counts: current[:counts],
      protected_counts: protected_counts,
      audit_counts: audit_counts,
      blob_purge_failures: blob_result[:failures],
      remaining_blob_ids: blob_result[:remaining_blob_ids],
      inventory_hash: current[:hash]
    }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError => e
    fail!("DELETE_FAILED:#{e.class}")
  end

  # Purge idempotente e exato. Um blob ainda referenciado por ActiveStorage
  # permanece pendente (nunca é removido por engano). Falha transitória mantém
  # o id na lista de retry, sem declarar sucesso.
  def purge_blobs(blob_ids:) # rubocop:disable Metrics/MethodLength
    ids = normalize_blob_ids(blob_ids)
    failures = 0
    ids.each do |blob_id|
      blob = ActiveStorage::Blob.find_by(id: blob_id)
      next if blob.nil?

      if ActiveStorage::Attachment.exists?(blob_id: blob_id)
        failures += 1
        next
      end

      begin
        purge_blob(blob)
      rescue ActiveStorage::FileNotFoundError
        blob.delete
      rescue StandardError
        failures += 1
      end
    end
    remaining = ActiveStorage::Blob.where(id: ids).order(:id).pluck(:id)
    {
      status: remaining.empty? ? 'committed' : 'committed_blob_pending',
      failures: failures,
      remaining_blob_ids: remaining
    }
  end

  private

  def inventory # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    accounts = Account.where(id: @account_ids).order(:id).pluck(:id)
    fail!('ACCOUNT_SET_MISMATCH') unless accounts == @account_ids

    conversation_ids = Conversation.where(account_id: @account_ids).order(:id).pluck(:id)
    message_ids = Message.where(conversation_id: conversation_ids).order(:id).pluck(:id)
    legacy_attachment_ids = Attachment.where(message_id: message_ids).order(:id).pluck(:id)
    blob_ids = active_storage_blob_ids(message_ids, legacy_attachment_ids)
    scope_ids = Connecta::Scope::ConversationScope.where(conversation_id: conversation_ids)
                                                  .order(:conversation_id).pluck(:conversation_id)
    protected = protected_counts
    audits = audit_counts
    payload = {
      version: 1, account_ids: @account_ids,
      conversation_ids: conversation_ids, message_ids: message_ids,
      legacy_attachment_ids: legacy_attachment_ids, blob_ids: blob_ids,
      scope_ids: scope_ids, protected_counts: protected, audit_counts: audits
    }
    {
      payload: payload,
      hash: Digest::SHA256.hexdigest(JSON.generate(payload)),
      counts: {
        conversations: conversation_ids.length,
        messages: message_ids.length,
        legacy_attachments: legacy_attachment_ids.length,
        active_storage_blobs: blob_ids.length,
        active_storage_bytes: ActiveStorage::Blob.where(id: blob_ids).sum(:byte_size).to_i,
        conversation_scopes: scope_ids.length
      },
      protected_counts: protected,
      audit_counts: audits,
      dependencies: {
        conversation: dependent_associations(Conversation),
        message: dependent_associations(Message)
      },
      destroy_callbacks: destroy_callbacks
    }
  end

  # Remove apenas os vínculos ActiveStorage dos alvos, sem purge_later. Isso
  # impede que um rollback restaure a conversa com o blob já apagado por um job
  # enfileirado dentro da transação. O blob em si só é purgado após o commit.
  def detach_active_storage_rows!(payload)
    ActiveStorage::Attachment.where(record_type: 'Message', record_id: payload[:message_ids]).delete_all
    ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: payload[:legacy_attachment_ids]).delete_all
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def verify_targets_gone!(payload, before_protected, before_audit)
    fail!('TARGET_CONVERSATIONS_REMAIN') unless Conversation.where(id: payload[:conversation_ids]).count.zero?
    fail!('NEW_MESSAGE_DURING_APPLY') unless Message.where(conversation_id: payload[:conversation_ids]).count.zero?
    fail!('TARGET_LEGACY_ATTACHMENTS_REMAIN') unless Attachment.where(id: payload[:legacy_attachment_ids]).count.zero?

    remaining_scope = Conversation.where(account_id: @account_ids)
    remaining_scope = remaining_scope.where.not(id: payload[:conversation_ids]) if payload[:conversation_ids].any?
    fail!('NEW_CONVERSATION_DURING_APPLY') unless remaining_scope.count.zero?
    fail!('PROTECTED_INVARIANT_FAILED') unless protected_counts == before_protected
    after_audit = audit_counts
    @audit_tables.each do |table|
      fail!("AUDIT_INVARIANT_FAILED:#{table}") if after_audit[table].to_i < before_audit[table].to_i
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def active_storage_blob_ids(message_ids, legacy_attachment_ids)
    (
      ActiveStorage::Attachment.where(record_type: 'Message', record_id: message_ids).pluck(:blob_id) +
      ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: legacy_attachment_ids).pluck(:blob_id)
    ).uniq.sort
  end

  def protected_counts
    @protected_tables.index_with { |table| count_table(table, 'PROTECTED_COUNT_FAILED') }
  end

  def audit_counts
    @audit_tables.index_with { |table| count_table(table, 'AUDIT_COUNT_FAILED') }
  end

  def count_table(table, error_prefix)
    ActiveRecord::Base.connection.select_value("SELECT count(*) FROM #{table}").to_i
  rescue StandardError
    fail!("#{error_prefix}:#{table}")
  end

  def dependent_associations(model)
    model.reflect_on_all_associations.filter_map do |association|
      dependent = association.options[:dependent]
      next unless dependent

      [association.name.to_s, association.macro.to_s, dependent.to_s, association.klass.name]
    rescue StandardError
      [association.name.to_s, association.macro.to_s, dependent.to_s, 'unknown']
    end
  end

  def destroy_callbacks
    Conversation._destroy_callbacks.map { |callback| callback.filter.to_s }
  rescue StandardError
    []
  end

  def ensure_protected_dependencies!
    [Conversation, Message].each do |model|
      dependent_associations(model).each do |name, _macro, _dependent, klass|
        next unless PROTECTED_DEPENDENT_MODELS.include?(klass)

        fail!("PROTECTED_DEPENDENT:#{model.name}.#{name}:#{klass}")
      end
    end
  end

  def normalize_account_ids(value) # rubocop:disable Metrics/CyclomaticComplexity
    ids = Array(value).map { |id| normalize_id(id) }
    fail!('ACCOUNT_IDS_REQUIRED') if ids.empty? || ids.any?(&:nil?)
    fail!('ACCOUNT_IDS_INVALID') unless ids.all?(&:positive?)

    ids = ids.uniq.sort
    fail!('TOO_MANY_ACCOUNTS') if ids.length > MAX_ACCOUNTS

    ids
  end

  def normalize_blob_ids(value)
    ids = Array(value).map { |id| normalize_id(id) }
    fail!('BLOB_IDS_INVALID') if ids.any?(&:nil?) || !ids.all?(&:positive?)

    ids.uniq.sort
  end

  def normalize_id(value)
    return value if value.is_a?(Integer)

    Integer(value, 10)
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_tables(tables, error)
    values = Array(tables).map(&:to_s)
    fail!(error) if values.empty? || !values.all? { |table| table.match?(TABLE_PATTERN) }

    values.freeze
  end

  def purge_blob(blob)
    blob.purge
  end

  def fail!(code)
    raise Blocked, code
  end
end
