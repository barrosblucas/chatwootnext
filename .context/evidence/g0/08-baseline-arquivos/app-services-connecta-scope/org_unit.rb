class Connecta::Scope::OrgUnit < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_org_units'

  belongs_to :parent, class_name: 'Connecta::Scope::OrgUnit', optional: true
end
