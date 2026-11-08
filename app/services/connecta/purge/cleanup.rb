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
# - purge_blobs(blobs:) => retry exato do manifesto opaco {id,key,service_name},
#   sem tocar no banco de conversas.
class Connecta::Purge::Cleanup # rubocop:disable Metrics/ClassLength
  class Blocked < StandardError; end

  PROTECTED_TABLES = %w[
    accounts users account_users inboxes inbox_members contacts contact_inboxes
    agent_bots agent_bot_inboxes teams labels webhooks channel_whatsapp
    installation_configs connecta_scoped_inboxes connecta_user_grants
    connecta_user_auth_epochs connecta_acl_sync_state
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

    def purge_blobs(blobs:)
      new(account_ids: nil, skip_account_validation: true).purge_blobs(blobs: blobs)
    end
  end

  def initialize(account_ids:, protected_tables: PROTECTED_TABLES, audit_tables: AUDIT_TABLES,
                 skip_account_validation: false)
    @account_ids = skip_account_validation ? [] : normalize_account_ids(account_ids)
    @protected_tables = immutable_tables(protected_tables, PROTECTED_TABLES, 'PROTECTED_TABLES_IMMUTABLE')
    @audit_tables = immutable_tables(audit_tables, AUDIT_TABLES, 'AUDIT_TABLES_IMMUTABLE')
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

  def apply(expected_hash:, confirmation:, writers_stopped:) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
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

    # O manifesto foi capturado ANTES do commit, com key/service_name. Nunca
    # dependemos da row do Blob (Blob#purge pode destruí-la) para o retry.
    blob_result = purge_blobs(blobs: payload[:blobs])
    {
      status: blob_result[:status] == 'committed' ? 'committed' : 'committed_blob_pending',
      counts: current[:counts],
      protected_counts: protected_counts,
      audit_counts: audit_counts,
      blob_purge_failures: blob_result[:failures],
      remaining_blobs: blob_result[:remaining_blobs],
      remaining_blob_ids: blob_result[:remaining_blobs].map { |entry| entry.fetch(:id) },
      inventory_hash: current[:hash]
    }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError => e
    fail!("DELETE_FAILED:#{e.class}")
  end

  # Purge idempotente e exato por manifesto opaco {id,key,service_name}. A row
  # do Blob só é removida DEPOIS de o storage confirmar delete/ausência; falha
  # transitória mantém o manifesto inteiro para retry, inclusive se a row já
  # tiver sumido.
  def purge_blobs(blobs:) # rubocop:disable Metrics/MethodLength
    manifest = normalize_blob_manifest(blobs)
    failures = 0
    pending = []
    manifest.each do |entry|
      if ActiveStorage::Attachment.exists?(blob_id: entry[:id])
        failures += 1
        pending << entry
        next
      end

      begin
        purge_manifest_entry!(entry)
      rescue StandardError
        failures += 1
        pending << entry
      end
    end
    {
      status: pending.empty? ? 'committed' : 'committed_blob_pending',
      failures: failures,
      remaining_blobs: pending
    }
  end

  private

  def inventory # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    accounts = Account.where(id: @account_ids).order(:id).pluck(:id)
    fail!('ACCOUNT_SET_MISMATCH') unless accounts == @account_ids

    conversation_ids = Conversation.where(account_id: @account_ids).order(:id).pluck(:id)
    message_ids = Message.where(conversation_id: conversation_ids).order(:id).pluck(:id)
    legacy_attachment_ids = Attachment.where(message_id: message_ids).order(:id).pluck(:id)
    scheduled_ids = ScheduledMessage.where(conversation_id: conversation_ids).order(:id).pluck(:id)
    recurring_ids = RecurringScheduledMessage.where(conversation_id: conversation_ids).order(:id).pluck(:id)
    attachment_rows = active_storage_attachment_rows(message_ids, legacy_attachment_ids, scheduled_ids, recurring_ids)
    attachments = attachment_rows.map { |row| { id: row.id, blob_id: row.blob_id } }
    blobs = blob_manifest(attachment_rows.map(&:blob_id))
    scope_ids = Connecta::Scope::ConversationScope.where(conversation_id: conversation_ids)
                                                  .order(:conversation_id).pluck(:conversation_id)
    protected = protected_counts
    audits = audit_counts
    payload = {
      version: 2, account_ids: @account_ids,
      conversation_ids: conversation_ids, message_ids: message_ids,
      legacy_attachment_ids: legacy_attachment_ids,
      scheduled_message_ids: scheduled_ids, recurring_scheduled_message_ids: recurring_ids,
      active_storage_attachment_ids: attachments.map { |entry| entry.fetch(:id) },
      attachments: attachments, blobs: blobs,
      scope_ids: scope_ids, protected_counts: protected, audit_counts: audits
    }
    {
      payload: payload,
      hash: Digest::SHA256.hexdigest(JSON.generate(payload)),
      counts: {
        conversations: conversation_ids.length,
        messages: message_ids.length,
        legacy_attachments: legacy_attachment_ids.length,
        scheduled_messages: scheduled_ids.length,
        recurring_scheduled_messages: recurring_ids.length,
        active_storage_attachments: attachments.length,
        active_storage_blobs: blobs.length,
        active_storage_bytes: ActiveStorage::Blob.where(id: blobs.map { |entry| entry.fetch(:id) }).sum(:byte_size).to_i,
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

  # Remove apenas os vínculos ActiveStorage inventariados, sem purge_later. O
  # blob em si só é tocado após o commit; um rollback restaura os vínculos e
  # nenhum job de purge foi enfileirado.
  def detach_active_storage_rows!(payload)
    current_ids = active_storage_attachment_rows(
      payload[:message_ids], payload[:legacy_attachment_ids],
      payload[:scheduled_message_ids], payload[:recurring_scheduled_message_ids]
    ).map(&:id)
    fail!('ACTIVE_STORAGE_CHANGED') unless current_ids.sort == payload[:active_storage_attachment_ids].sort

    ActiveStorage::Attachment.where(id: payload[:active_storage_attachment_ids]).delete_all
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def verify_targets_gone!(payload, before_protected, before_audit)
    fail!('TARGET_CONVERSATIONS_REMAIN') unless Conversation.where(id: payload[:conversation_ids]).count.zero?
    fail!('NEW_MESSAGE_DURING_APPLY') unless Message.where(conversation_id: payload[:conversation_ids]).count.zero?
    fail!('TARGET_LEGACY_ATTACHMENTS_REMAIN') unless Attachment.where(id: payload[:legacy_attachment_ids]).count.zero?
    fail!('TARGET_SCHEDULED_REMAIN') unless ScheduledMessage.where(id: payload[:scheduled_message_ids]).count.zero?
    fail!('TARGET_RECURRING_REMAIN') unless RecurringScheduledMessage.where(id: payload[:recurring_scheduled_message_ids]).count.zero?
    verify_active_storage_gone!(payload)

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

  def verify_active_storage_gone!(payload)
    fail!('TARGET_ACTIVE_STORAGE_ATTACHMENTS_REMAIN') unless ActiveStorage::Attachment.where(id: payload[:active_storage_attachment_ids]).count.zero?
    race = ActiveStorage::Attachment
           .where(record_type: 'Message', record_id: payload[:message_ids])
           .or(ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: payload[:legacy_attachment_ids]))
           .or(ActiveStorage::Attachment.where(record_type: 'ScheduledMessage', record_id: payload[:scheduled_message_ids]))
           .or(ActiveStorage::Attachment.where(record_type: 'RecurringScheduledMessage',
                                               record_id: payload[:recurring_scheduled_message_ids]))
    fail!('NEW_ACTIVE_STORAGE_ATTACHMENT_DURING_APPLY') unless race.count.zero?
  end

  def active_storage_attachment_rows(message_ids, legacy_attachment_ids, scheduled_ids, recurring_ids)
    ActiveStorage::Attachment
      .where(record_type: 'Message', record_id: message_ids)
      .or(ActiveStorage::Attachment.where(record_type: 'Attachment', record_id: legacy_attachment_ids))
      .or(ActiveStorage::Attachment.where(record_type: 'ScheduledMessage', record_id: scheduled_ids))
      .or(ActiveStorage::Attachment.where(record_type: 'RecurringScheduledMessage', record_id: recurring_ids))
      .order(:id).to_a
  end

  def blob_manifest(blob_ids)
    ids = blob_ids.uniq
    blobs = ActiveStorage::Blob.where(id: ids).order(:id).to_a
    missing = ids - blobs.map(&:id)
    fail!("BLOB_METADATA_MISSING:#{missing.length}") if missing.any?

    blobs.map do |blob|
      { id: blob.id, key: blob.key, service_name: blob.service_name }
    end
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

  def normalize_blob_manifest(value) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    entries = Array(value).map do |raw|
      next nil unless raw.is_a?(Hash) || raw.respond_to?(:to_h)

      entry = raw.to_h.symbolize_keys
      id = normalize_id(entry[:id])
      key = entry[:key].to_s
      service_name = entry[:service_name].to_s
      next nil unless id&.positive? && key.present? && service_name.present?

      { id: id, key: key, service_name: service_name }
    end
    fail!('BLOB_MANIFEST_INVALID') if entries.any?(&:nil?)

    entries.compact.uniq { |entry| entry[:id] }.sort_by { |entry| entry[:id] }
  end

  def purge_manifest_entry!(entry)
    services = ActiveStorage::Blob.services
    service = fetch_storage_service(services, entry[:service_name])
    fail!('STORAGE_SERVICE_UNKNOWN') if service.nil?
    delete_variants!(service, entry[:key])
    if service.respond_to?(:exist?) && !service.exist?(entry[:key])
      delete_blob_metadata!(entry[:id])
      return
    end

    service.delete(entry[:key])
    delete_blob_metadata!(entry[:id])
  rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
    # Ausência comprovada do objeto: só então remove a metadata.
    delete_blob_metadata!(entry[:id])
  end

  def fetch_storage_service(services, name)
    services.fetch(name)
  rescue KeyError
    begin
      services.fetch(name.to_sym)
    rescue StandardError
      nil
    end
  end

  def delete_variants!(service, key)
    return unless service.respond_to?(:delete_prefixed)

    service.delete_prefixed("variants/#{key}/")
  rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
    nil
  end

  def delete_blob_metadata!(blob_id)
    ActiveStorage::VariantRecord.where(blob_id: blob_id).delete_all
    ActiveStorage::Blob.where(id: blob_id).delete_all
  end

  def normalize_id(value)
    return value if value.is_a?(Integer)

    Integer(value, 10)
  rescue ArgumentError, TypeError
    nil
  end

  def immutable_tables(value, constant, error)
    values = Array(value).map(&:to_s)
    fail!(error) unless values == constant

    constant
  end

  def fail!(code)
    raise Blocked, code
  end
end
