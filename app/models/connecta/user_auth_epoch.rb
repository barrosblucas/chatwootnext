# == Schema Information
#
# Table name: connecta_user_auth_epochs
#
#  id                 :bigint           not null, primary key
#  epoch              :integer          default(1), not null
#  revoked_locally_at :datetime
#  source             :string           default("platform"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_connecta_user_auth_epochs_on_user_id  (user_id) UNIQUE
#
class Connecta::UserAuthEpoch < Connecta::BaseRecord
  self.table_name = 'connecta_user_auth_epochs'

  SOURCES = %w[platform emergency].freeze

  validates :epoch, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source, inclusion: { in: SOURCES }
end
