# == Schema Information
#
# Table name: connecta_access_audits
#
#  id              :bigint           not null, primary key
#  access_path     :string           not null
#  decision        :string           not null
#  surface         :string           not null
#  created_at      :datetime         not null
#  conversation_id :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_connecta_access_audits_on_conversation_id_and_created_at  (conversation_id,created_at)
#  index_connecta_access_audits_on_user_id_and_created_at          (user_id,created_at)
#
class Connecta::AccessAudit < Connecta::BaseRecord
  self.table_name = 'connecta_access_audits'

  ACCESS_PATHS = %w[admin grant].freeze
  DECISIONS = %w[allow deny].freeze

  validates :surface, presence: true
  validates :access_path, inclusion: { in: ACCESS_PATHS }
  validates :decision, inclusion: { in: DECISIONS }

  def readonly?
    persisted? || super
  end
end
