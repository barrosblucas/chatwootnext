# == Schema Information
#
# Table name: connecta_scoped_inboxes
#
#  id          :bigint           not null, primary key
#  enforcement :string           default("enforce"), not null
#  maintenance :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  inbox_id    :bigint           not null
#
# Indexes
#
#  index_connecta_scoped_inboxes_on_inbox_id  (inbox_id) UNIQUE
#
class Connecta::ScopedInbox < Connecta::BaseRecord
  self.table_name = 'connecta_scoped_inboxes'

  # T3.9: admin_only nega toda superfície escopada a não-admin; maintenance
  # bloqueia envio humano com 409 (entrada continua gravada).
  ENFORCEMENTS = %w[enforce admin_only maintenance].freeze

  validates :enforcement, inclusion: { in: ENFORCEMENTS }

  def maintenance_mode?
    maintenance || enforcement == 'maintenance'
  end

  def admin_only?
    enforcement == 'admin_only'
  end
end
