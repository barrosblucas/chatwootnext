class AddGrantTombstonesToConnectaAcl < ActiveRecord::Migration[7.0]
  # B3/Q7.5 (fork-side ACL robustness): identifica cada grant pelo `grant_id`
  # do WP (`staff_grants.id`, uuid string) e guarda lápides de grants
  # revogados. Aditiva: coluna anulável + tabela nova; nenhum dado apagado.
  def up
    add_column :connecta_user_grants, :grant_id, :string unless column_exists?(:connecta_user_grants, :grant_id)
    unless index_exists?(:connecta_user_grants, :grant_id, name: 'idx_connecta_user_grants_grant_id')
      add_index :connecta_user_grants, :grant_id, name: 'idx_connecta_user_grants_grant_id'
    end

    create_table :connecta_revoked_grants, id: false do |t|
      t.string :grant_id, null: false
      t.bigint :user_id
      t.uuid :org_unit_id
      t.string :permission
      t.datetime :revoked_at, null: false
      t.timestamps
    end
    execute('ALTER TABLE connecta_revoked_grants ADD PRIMARY KEY (grant_id)')
    unless index_exists?(:connecta_revoked_grants, %i[user_id org_unit_id permission],
                         name: 'idx_connecta_revoked_grants_triple')
      add_index :connecta_revoked_grants, %i[user_id org_unit_id permission], name: 'idx_connecta_revoked_grants_triple'
    end
  end

  def down
    if index_exists?(:connecta_revoked_grants, %i[user_id org_unit_id permission], name: 'idx_connecta_revoked_grants_triple')
      remove_index :connecta_revoked_grants, name: 'idx_connecta_revoked_grants_triple'
    end
    drop_table :connecta_revoked_grants if table_exists?(:connecta_revoked_grants)
    if index_exists?(:connecta_user_grants, :grant_id, name: 'idx_connecta_user_grants_grant_id')
      remove_index :connecta_user_grants, name: 'idx_connecta_user_grants_grant_id'
    end
    remove_column :connecta_user_grants, :grant_id if column_exists?(:connecta_user_grants, :grant_id)
  end
end
