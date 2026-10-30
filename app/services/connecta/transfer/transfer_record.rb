# Registro da transferência do spike G0 (T0.7), tabela connecta_g0_transfers. Não é modelo de produto.
class Connecta::Transfer::TransferRecord < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_transfers'

  STATES = %w[requested awaiting_dispatch prepared rejected unknown committed_local committed aborted activation_stuck].freeze

  validates :state, inclusion: { in: STATES }
end
