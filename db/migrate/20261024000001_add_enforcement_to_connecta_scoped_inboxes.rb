class AddEnforcementToConnectaScopedInboxes < ActiveRecord::Migration[7.0]
  # T3.9: coluna de contenção em connecta_scoped_inboxes. Aditiva e
  # idempotente: ignora se o timestamp 20261024000000 já criou a coluna,
  # preenche legado nulo e só então impõe default + NOT NULL.
  def up
    add_column :connecta_scoped_inboxes, :enforcement, :string, default: 'enforce' unless column_exists?(:connecta_scoped_inboxes, :enforcement)
    execute "UPDATE connecta_scoped_inboxes SET enforcement = 'enforce' WHERE enforcement IS NULL"
    change_column_default :connecta_scoped_inboxes, :enforcement, from: nil, to: 'enforce'
    change_column_null :connecta_scoped_inboxes, :enforcement, false, 'enforce'
  end

  def down
    # Coluna de segurança: remover reverteria a contenção. Mantida no rollback.
  end
end
