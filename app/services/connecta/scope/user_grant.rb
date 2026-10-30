class Connecta::Scope::UserGrant < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_user_grants'

  PERMISSIONS = %w[acompanhar atender admin_nominal].freeze

  belongs_to :org_unit, class_name: 'Connecta::Scope::OrgUnit'

  validates :permission, inclusion: { in: PERMISSIONS }
end
