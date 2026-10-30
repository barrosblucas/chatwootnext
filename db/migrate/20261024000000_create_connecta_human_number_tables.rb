class CreateConnectaHumanNumberTables < ActiveRecord::Migration[7.0]
  NON_TERMINAL_SCOPE_STATES = %w[reception active transferring pending_activation activation_stuck].freeze
  OPEN_TRANSFER_STATES = %w[requested awaiting_dispatch prepared unknown committed_local activation_stuck].freeze

  # Migração declarativa de DDL (tabelas, índices, checks); dividir em métodos não muda a ordem das criações.
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :connecta_scoped_inboxes do |t|
      t.bigint :inbox_id, null: false
      t.string :enforcement, null: false, default: 'enforce'
      t.boolean :maintenance, null: false, default: false
      t.timestamps
    end
    add_index :connecta_scoped_inboxes, :inbox_id, unique: true

    create_table :connecta_org_units, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.uuid :parent_id
      t.string :path, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    add_index :connecta_org_units, :path, unique: true

    create_table :connecta_user_grants do |t|
      t.bigint :user_id, null: false
      t.uuid :org_unit_id, null: false
      t.string :permission, null: false
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    add_index :connecta_user_grants, %i[user_id org_unit_id permission], unique: true, name: 'idx_connecta_user_grants_unique'

    create_table :connecta_user_auth_epochs do |t|
      t.bigint :user_id, null: false
      t.integer :epoch, null: false, default: 1
      t.datetime :revoked_locally_at
      t.string :source, null: false, default: 'platform'
      t.timestamps
    end
    add_index :connecta_user_auth_epochs, :user_id, unique: true

    create_table :connecta_acl_sync_state do |t|
      t.integer :last_version, null: false, default: 0
      t.datetime :last_heartbeat_at
      t.timestamps
    end
    add_index :connecta_acl_sync_state, :id, unique: true, where: 'id = 1', name: 'idx_connecta_acl_sync_singleton'

    create_table :connecta_conversation_scopes do |t|
      t.bigint :conversation_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :contact_id, null: false
      t.uuid :org_unit_id, null: false
      t.string :state, null: false
      t.string :case_protocol
      t.string :platform_session_ref
      t.integer :case_version, null: false, default: 0
      t.uuid :transfer_id
      t.datetime :activated_at
      t.datetime :closed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :connecta_conversation_scopes, :conversation_id, unique: true
    add_index :connecta_conversation_scopes, %i[inbox_id contact_id], unique: true,
                                                                      where: "state IN (#{NON_TERMINAL_SCOPE_STATES.map do |state|
                                                                        "'#{state}'"
                                                                      end.join(', ')})",
                                                                      name: 'idx_connecta_scopes_open_inbox_contact'

    create_table :connecta_transfers, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.bigint :source_conversation_id, null: false
      t.bigint :destination_conversation_id
      t.uuid :source_org_unit_id
      t.uuid :destination_org_unit_id, null: false
      t.bigint :actor_user_id
      t.string :state, null: false
      t.string :summary_sha256
      t.integer :summary_length
      t.integer :target_case_version
      t.string :platform_session_ref
      t.datetime :prepared_at
      t.datetime :committed_local_at
      t.datetime :committed_at
      t.datetime :resolved_at
      t.bigint :resolved_by
      t.timestamps
    end
    add_index :connecta_transfers, :source_conversation_id, unique: true,
                                                            where: "state IN (#{OPEN_TRANSFER_STATES.map { |state| "'#{state}'" }.join(', ')})",
                                                            name: 'idx_connecta_transfers_open_source'

    create_table :connecta_outbound_dispatches do |t|
      t.bigint :message_id, null: false
      t.bigint :conversation_id, null: false
      t.string :state, null: false
      t.string :connector_message_id
      t.datetime :attempted_at
      t.datetime :resolved_at
      t.bigint :resolved_by
      t.timestamps
    end
    add_index :connecta_outbound_dispatches, :message_id, unique: true

    create_table :connecta_outbox do |t|
      t.string :dedupe_key, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :connecta_outbox, :dedupe_key, unique: true
    add_index :connecta_outbox, %i[status created_at]

    create_table :connecta_access_audits do |t|
      t.bigint :user_id, null: false
      t.bigint :conversation_id
      t.string :surface, null: false
      t.string :access_path, null: false
      t.string :decision, null: false
      t.datetime :created_at, null: false
    end
    add_index :connecta_access_audits, %i[conversation_id created_at]
    add_index :connecta_access_audits, %i[user_id created_at]
  end
end
