# == Schema Information
#
# Table name: connecta_org_units
#
#  id         :uuid             not null, primary key
#  enabled    :boolean          default(TRUE), not null
#  name       :string           not null
#  path       :string           not null
#  version    :integer          default(1), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  parent_id  :uuid
#
# Indexes
#
#  index_connecta_org_units_on_path  (path) UNIQUE
#
class Connecta::OrgUnit < Connecta::BaseRecord
  self.table_name = 'connecta_org_units'

  belongs_to :parent, class_name: 'Connecta::OrgUnit', optional: true
  # Sem dependent: nunca apagar filhos nem grants em cascata (dado do núcleo; exclusão exige decisão explícita).
  has_many :children, class_name: 'Connecta::OrgUnit', foreign_key: :parent_id, inverse_of: :parent # rubocop:disable Rails/HasManyOrHasOneDependent
  has_many :user_grants, class_name: 'Connecta::UserGrant', inverse_of: :org_unit # rubocop:disable Rails/HasManyOrHasOneDependent

  validates :name, :path, presence: true
end
