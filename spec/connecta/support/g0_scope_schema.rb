# Schema do protótipo G0 de escopo: só cria tabelas connecta_g0_* que faltam (create-only). Não altera tabelas do core,
# não toca db/schema.rb nem schema_migrations, e não remove nada. Roda só depois do guarda G0 (ver spec).
module Connecta::G0ScopeSchema
  module_function

  NON_TERMINAL = "'reception', 'active', 'transferring', 'pending_activation', 'activation_stuck'".freeze

  def ensure!
    scoped_inboxes
    org_units
    user_grants
    user_auth_epochs
    acl_sync_state
    conversation_scopes
    access_audits
  end

  def scoped_inboxes
    connection.create_table(:connecta_g0_scoped_inboxes, if_not_exists: true) do |t|
      t.bigint :inbox_id, null: false
      t.string :enforcement, null: false
      t.boolean :maintenance, null: false, default: false
      t.timestamps
    end
    connection.add_index(:connecta_g0_scoped_inboxes, :inbox_id, unique: true, name: 'idx_g0_scoped_inbox', if_not_exists: true)
  end

  def org_units
    connection.create_table(:connecta_g0_org_units, if_not_exists: true) do |t|
      t.string :name, null: false
      t.bigint :parent_id
      t.string :path, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    connection.add_index(:connecta_g0_org_units, :path, unique: true, name: 'idx_g0_org_units_path', if_not_exists: true)
  end

  def user_grants
    connection.create_table(:connecta_g0_user_grants, if_not_exists: true) do |t|
      t.bigint :user_id, null: false
      t.bigint :org_unit_id, null: false
      t.string :permission, null: false
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    connection.add_index(:connecta_g0_user_grants, %i[user_id org_unit_id permission], unique: true, name: 'idx_g0_grants_unique',
                                                                                       if_not_exists: true)
  end

  def user_auth_epochs
    connection.create_table(:connecta_g0_user_auth_epochs, if_not_exists: true) do |t|
      t.bigint :user_id, null: false
      t.integer :epoch, null: false, default: 1
      t.datetime :revoked_locally_at
      t.timestamps
    end
    connection.add_index(:connecta_g0_user_auth_epochs, :user_id, unique: true, name: 'idx_g0_auth_epoch_user', if_not_exists: true)
  end

  def acl_sync_state
    connection.create_table(:connecta_g0_acl_sync_state, if_not_exists: true) do |t|
      t.integer :last_version, null: false, default: 0
      t.datetime :last_heartbeat_at
      t.timestamps
    end
  end

  def conversation_scopes
    connection.create_table(:connecta_g0_conversation_scopes, if_not_exists: true) do |t|
      t.bigint :conversation_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :org_unit_id, null: false
      t.string :state, null: false
      t.string :case_protocol
      t.integer :case_version, null: false, default: 0
      t.datetime :closed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    connection.add_index(:connecta_g0_conversation_scopes, :conversation_id, unique: true, name: 'idx_g0_scope_conversation',
                                                                             if_not_exists: true)
    connection.add_index(:connecta_g0_conversation_scopes, %i[inbox_id contact_id], unique: true, name: 'idx_g0_scope_inbox_contact_open',
                                                                                    where: "state IN (#{NON_TERMINAL})", if_not_exists: true)
  end

  def access_audits
    connection.create_table(:connecta_g0_access_audits, if_not_exists: true) do |t|
      t.bigint :user_id, null: false
      t.bigint :conversation_id
      t.string :surface, null: false
      t.string :access_path, null: false
      t.string :decision, null: false
      t.datetime :created_at, null: false
    end
  end

  def connection
    ActiveRecord::Base.connection
  end
end
