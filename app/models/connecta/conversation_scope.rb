# == Schema Information
#
# Table name: connecta_conversation_scopes
#
#  id                   :bigint           not null, primary key
#  activated_at         :datetime
#  case_protocol        :string
#  case_version         :integer          default(0), not null
#  closed_at            :datetime
#  lock_version         :integer          default(0), not null
#  platform_session_ref :string
#  state                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  contact_id           :bigint           not null
#  conversation_id      :bigint           not null
#  inbox_id             :bigint           not null
#  org_unit_id          :uuid             not null
#  transfer_id          :uuid
#
# Indexes
#
#  idx_connecta_scopes_open_inbox_contact                 (inbox_id,contact_id) UNIQUE WHERE
#    ((state)::text = ANY (ARRAY[('reception'::character varying)::text, ('active'::character varying)::text,
#    ('transferring'::character varying)::text, ('pending_activation'::character varying)::text,
#    ('activation_stuck'::character varying)::text]))
#  index_connecta_conversation_scopes_on_conversation_id  (conversation_id) UNIQUE
#
class Connecta::ConversationScope < Connecta::BaseRecord
  self.table_name = 'connecta_conversation_scopes'

  STATES = %w[reception active transferring pending_activation activation_stuck transferred_out closed abandoned_triage].freeze
  NON_TERMINAL_STATES = %w[reception active transferring pending_activation activation_stuck].freeze
  AGENT_READ_STATES = %w[reception active transferring].freeze

  belongs_to :org_unit, class_name: 'Connecta::OrgUnit'

  validates :state, inclusion: { in: STATES }
end
