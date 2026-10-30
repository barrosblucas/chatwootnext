class Connecta::Scope::ScopedInbox < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_scoped_inboxes'

  ENFORCEMENTS = %w[enforce admin_only].freeze

  validates :enforcement, inclusion: { in: ENFORCEMENTS }
end
