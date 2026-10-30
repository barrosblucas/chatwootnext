class Connecta::Scope::ScopedInbox < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_scoped_inboxes'

  # T3.9: admin_only nega toda superfície escopada a não-admin (inclusive membro
  # da inbox ou com team_id forçado); maintenance bloqueia envio humano com 409.
  ENFORCEMENTS = %w[enforce admin_only maintenance].freeze

  validates :enforcement, inclusion: { in: ENFORCEMENTS }

  # maintenance herdado (boolean legado): equivale ao modo maintenance.
  def maintenance_mode?
    maintenance || enforcement == 'maintenance'
  end

  def admin_only?
    enforcement == 'admin_only'
  end

  # A tabela G0 não tem FK para inboxes (spike), então a ligação com a conta passa pela consulta de inboxes.
  def self.account_marked?(account_id)
    exists?(inbox_id: ::Inbox.where(account_id: account_id).select(:id))
  end
end
