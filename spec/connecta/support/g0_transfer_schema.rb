# Schema do spike G0 de transferência (T0.7): só cria as tabelas connecta_g0_transfers e connecta_g0_outbound_dispatches
# que faltam (create-only). Não altera tabelas do core, não toca db/schema.rb nem schema_migrations, e não remove nada.
# Roda só depois do guarda G0 (ver spec).
module Connecta::G0TransferSchema
  module_function

  OPEN_STATES = "'requested', 'awaiting_dispatch', 'prepared', 'unknown', 'committed_local', 'activation_stuck'".freeze

  def ensure!
    transfers
    outbound_dispatches
  end

  def transfers
    connection.create_table(:connecta_g0_transfers, id: :uuid, default: 'gen_random_uuid()', if_not_exists: true) do |t|
      t.bigint :source_conversation_id, null: false
      t.bigint :destination_conversation_id
      t.bigint :source_org_unit_id
      t.bigint :destination_org_unit_id, null: false
      t.bigint :actor_user_id
      t.string :state, null: false
      t.string :platform_session_ref
      t.integer :target_case_version
      t.string :summary_sha256
      t.timestamps
    end
    connection.add_index(:connecta_g0_transfers, :source_conversation_id, unique: true, name: 'idx_g0_transfers_open_source',
                                                                          where: "state IN (#{OPEN_STATES})", if_not_exists: true)
  end

  def outbound_dispatches
    connection.create_table(:connecta_g0_outbound_dispatches, if_not_exists: true) do |t|
      t.bigint :message_id, null: false
      t.bigint :conversation_id, null: false
      t.string :state, null: false
      t.string :connector_message_id
      t.datetime :attempted_at
      t.datetime :resolved_at
      t.bigint :resolved_by
      t.timestamps
    end
    connection.add_index(:connecta_g0_outbound_dispatches, :message_id, unique: true, name: 'idx_g0_dispatches_message', if_not_exists: true)
  end

  def connection
    ActiveRecord::Base.connection
  end
end
