# == Schema Information
#
# Table name: connecta_revoked_grants
#
#  grant_id   :string           not null, primary key
#  revoked_at :datetime         not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Connecta::RevokedGrant < Connecta::BaseRecord
  self.table_name = 'connecta_revoked_grants'
  self.primary_key = 'grant_id'

  validates :grant_id, presence: true, uniqueness: true
end
