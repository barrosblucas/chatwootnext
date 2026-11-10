# == Schema Information
#
# Table name: connecta_revoked_grants
#
#  grant_id    :string           not null, primary key
#  user_id     :bigint
#  org_unit_id :uuid
#  permission  :string
#  revoked_at  :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  idx_connecta_revoked_grants_triple  (user_id,org_unit_id,permission)
#
class Connecta::RevokedGrant < Connecta::BaseRecord
  self.table_name = 'connecta_revoked_grants'
  self.primary_key = 'grant_id'

  validates :grant_id, presence: true, uniqueness: true
end
