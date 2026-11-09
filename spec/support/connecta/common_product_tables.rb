# frozen_string_literal: true

# TEST-ONLY: mapeamento das tabelas de produto no runner comum do CI.
# Contexto: o CI comum sobe com CONNECTA_HUMAN_NUMBER_ENABLED=false, então
# Connecta::Runtime::G0Adapter.install! nunca roda e os modelos G0 mantêm
# table_name connecta_g0_* (inexistentes no DB comum, que só tem connecta_*
# via db:schema:load). O ActionCableListener#message_created chama
# Projection.marked? incondicionalmente, e qualquer spec transacional que cria
# Message quebra com tabela ausente.
# Este helper só age com CONNECTA_COMMON_PRODUCT_TABLES=1 (flag explícita do
# job comum em run_foss_spec.yml), apenas em Rails.env.test?, nunca no alvo F5
# (CONNECTA_G0_RUNNER=conecta-consolidacao-20261029-f5) e nunca instala hooks
# de produção (sem prepend, sem feature flip, sem mudar autorização). Se alguma
# tabela connecta_* esperada não existir, levanta alto em vez de mockar ou pular.
module Connecta
  module CommonProductTables
    FLAG = 'CONNECTA_COMMON_PRODUCT_TABLES'
    F5_RUNNER = 'conecta-consolidacao-20261029-f5'
    F5_ENV_KEY = 'CONNECTA_G0_RUNNER'

    module_function

    def f5_target?
      ENV[F5_ENV_KEY] == F5_RUNNER
    end

    def active?
      ENV[FLAG] == '1' && Rails.env.test? && !f5_target?
    end

    # Retargeta os modelos G0 às tabelas de produto existentes. Retorna true
    # quando ativa, false quando inativa (F5, flag ausente ou fora de test).
    # Levanta RuntimeError listando as tabelas ausentes, sem mock ou skip.
    def install!
      return false unless active?

      tables = Connecta::Runtime::G0Adapter::TABLES
      missing = tables.values.reject { |table| ActiveRecord::Base.connection.data_source_exists?(table) }
      raise "Connecta common test mapping: missing product tables (#{missing.join(', ')}); run db:schema:load first" if missing.any?

      tables.each do |model, table|
        model.table_name = table
        model.reset_column_information
      end
      true
    end
  end
end

# Auto-aplica no boot do suite comum (rails_helper carrega spec/support/**).
# No F5, sem flag ou fora de test, active? é false e nada muda.
Connecta::CommonProductTables.install!
