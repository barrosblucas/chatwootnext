class Connecta::Scope::ConversationScope < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_conversation_scopes'

  STATES = %w[reception active transferring transferred_out pending_activation activation_stuck closed].freeze
  # Agentes só leem nestes estados; escrita exige active (ver Gate).
  # closed (resolvido pelo operador) continua legível, mas nunca reutilizável nem gravável.
  READ_STATES = %w[reception active transferring closed].freeze
  NON_TERMINAL_STATES = %w[reception active transferring pending_activation activation_stuck].freeze

  belongs_to :org_unit, class_name: 'Connecta::Scope::OrgUnit'

  validates :state, inclusion: { in: STATES }
end
