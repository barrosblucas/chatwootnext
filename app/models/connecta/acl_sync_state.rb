# == Schema Information
#
# Table name: connecta_acl_sync_state
#
#  id                :bigint           not null, primary key
#  last_heartbeat_at :datetime
#  last_version      :integer          default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  idx_connecta_acl_sync_singleton  (id) UNIQUE WHERE (id = 1)
#
class Connecta::AclSyncState < Connecta::BaseRecord
  self.table_name = 'connecta_acl_sync_state'

  validates :last_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.heartbeat_fresh?(max_age: 60.seconds, now: Time.current)
    state = order(:id).first
    state.present? && state.last_heartbeat_at.present? && state.last_heartbeat_at >= now - max_age
  end
end
