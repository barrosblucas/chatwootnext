class Connecta::Scope::AccessAudit < Connecta::Scope::BaseRecord
  self.table_name = 'connecta_g0_access_audits'

  DECISIONS = %w[allow deny].freeze

  # Append-only: depois de gravado, o registro não é alterado nem removido.
  def readonly?
    persisted? || super
  end
end
