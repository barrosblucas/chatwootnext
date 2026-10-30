# == Schema Information
#
# Table name: connecta_outbound_dispatches
#
#  id                   :bigint           not null, primary key
#  attempted_at         :datetime
#  resolved_at          :datetime
#  resolved_by          :bigint
#  state                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  connector_message_id :string
#  conversation_id      :bigint           not null
#  message_id           :bigint           not null
#
# Indexes
#
#  index_connecta_outbound_dispatches_on_message_id  (message_id) UNIQUE
#
class Connecta::OutboundDispatch < Connecta::BaseRecord
  self.table_name = 'connecta_outbound_dispatches'

  STATES = %w[queued dispatching accepted failed uncertain parked].freeze

  belongs_to :conversation
  belongs_to :message

  validates :state, inclusion: { in: STATES }
end
