# == Schema Information
#
# Table name: connecta_transfers
#
#  id                          :uuid             not null, primary key
#  committed_at                :datetime
#  committed_local_at          :datetime
#  platform_session_ref        :string
#  prepared_at                 :datetime
#  resolved_at                 :datetime
#  resolved_by                 :bigint
#  state                       :string           not null
#  summary_length              :integer
#  summary_sha256              :string
#  target_case_version         :integer
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  actor_user_id               :bigint
#  destination_conversation_id :bigint
#  destination_org_unit_id     :uuid             not null
#  source_conversation_id      :bigint           not null
#  source_org_unit_id          :uuid
#
# Indexes
#
#  idx_connecta_transfers_open_source  (source_conversation_id) UNIQUE WHERE
#    ((state)::text = ANY (ARRAY[('requested'::character varying)::text, ('awaiting_dispatch'::character varying)::text,
#    ('prepared'::character varying)::text, ('unknown'::character varying)::text,
#    ('committed_local'::character varying)::text, ('activation_stuck'::character varying)::text]))
#
class Connecta::TransferRecord < Connecta::BaseRecord
  self.table_name = 'connecta_transfers'

  STATES = %w[requested awaiting_dispatch prepared unknown committed_local committed aborted rejected activation_stuck].freeze

  validates :state, inclusion: { in: STATES }
  validates :summary_sha256, format: { with: /\A[0-9a-f]{64}\z/i }, allow_nil: true
  validates :summary_length, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end
