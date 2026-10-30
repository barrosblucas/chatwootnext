# == Schema Information
#
# Table name: connecta_user_grants
#
#  id          :bigint           not null, primary key
#  permission  :string           not null
#  version     :integer          default(1), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  org_unit_id :uuid             not null
#  user_id     :bigint           not null
#
# Indexes
#
#  idx_connecta_user_grants_unique  (user_id,org_unit_id,permission) UNIQUE
#
class Connecta::UserGrant < Connecta::BaseRecord
  self.table_name = 'connecta_user_grants'

  PERMISSIONS = %w[acompanhar atender transferir admin_nominal].freeze

  belongs_to :org_unit, class_name: 'Connecta::OrgUnit', inverse_of: :user_grants

  validates :permission, inclusion: { in: PERMISSIONS }
end
