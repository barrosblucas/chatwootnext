# Registro do despacho de saída do spike G0 (T0.7), tabela connecta_g0_outbound_dispatches. Não é modelo de produto.
class Connecta::Transfer::OutboundDispatchRecord < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_outbound_dispatches'

  STATES = %w[queued dispatching accepted failed uncertain parked].freeze

  validates :state, inclusion: { in: STATES }
end
