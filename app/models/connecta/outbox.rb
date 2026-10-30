# == Schema Information
#
# Table name: connecta_outbox
#
#  id           :bigint           not null, primary key
#  attempts     :integer          default(0), not null
#  dedupe_key   :string           not null
#  delivered_at :datetime
#  event_type   :string           not null
#  payload      :jsonb            not null
#  status       :string           default("pending"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_connecta_outbox_on_dedupe_key             (dedupe_key) UNIQUE
#  index_connecta_outbox_on_status_and_created_at  (status,created_at)
#
class Connecta::Outbox < Connecta::BaseRecord
  self.table_name = 'connecta_outbox'

  STATUSES = %w[pending processing delivered failed].freeze

  validates :dedupe_key, :event_type, presence: true
  validates :status, inclusion: { in: STATUSES }
end
