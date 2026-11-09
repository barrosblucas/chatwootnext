# frozen_string_literal: true

require 'rails_helper'

# Cobertura do helper TEST-ONLY do runner comum (spec/support/connecta/common_product_tables.rb).
# Prova: modo comum mapeia para produto, F5 intacto, tabela ausente falha alto,
# e a fonte de produção Projection.marked? continua propagando erro (fail-closed).
# Não enfraquece sanitizer de mídia nem permissões; sem skip, sem mock de autorização.
RSpec.describe Connecta::CommonProductTables do # rubocop:disable RSpec/SpecFilePathFormat -- helper vive em spec/support/connecta; este spec roda no runner comum, fora da allowlist F5
  def g0_name(product_table)
    product_table.sub('connecta_', 'connecta_g0_')
  end

  def reset_to_g0!
    Connecta::Runtime::G0Adapter::TABLES.each_value do |product|
      model = Connecta::Runtime::G0Adapter::TABLES.key(product)
      model.table_name = g0_name(product)
      model.reset_column_information
    end
  end

  around do |example|
    saved_flag = ENV.fetch(described_class::FLAG, nil)
    saved_runner = ENV.fetch(described_class::F5_ENV_KEY, nil)
    saved_tables = Connecta::Runtime::G0Adapter::TABLES.keys.index_with(&:table_name)
    example.run
    if saved_flag.nil?
      ENV.delete(described_class::FLAG)
    else
      ENV[described_class::FLAG] = saved_flag
    end
    if saved_runner.nil?
      ENV.delete(described_class::F5_ENV_KEY)
    else
      ENV[described_class::F5_ENV_KEY] = saved_runner
    end
    saved_tables.each do |model, table|
      model.table_name = table
      model.reset_column_information
    end
  end

  it 'mapeia os modelos G0 às tabelas de produto no modo comum, sem instalar hooks' do
    ENV[described_class::FLAG] = '1'
    ENV.delete(described_class::F5_ENV_KEY)
    reset_to_g0!
    projection_ancestors_before = Connecta::Scope::Projection.ancestors.dup
    gate_ancestors_before = Connecta::Scope::Gate.ancestors.dup

    expect(described_class.install!).to be(true)

    Connecta::Runtime::G0Adapter::TABLES.each do |model, table|
      expect(model.table_name).to eq(table), "#{model} deveria apontar a #{table}"
    end
    expect(Connecta::Scope::Projection.ancestors).to eq(projection_ancestors_before)
    expect(Connecta::Scope::Gate.ancestors).to eq(gate_ancestors_before)
    expect(Connecta::Scope::Projection.ancestors).not_to include(Connecta::Runtime::G0Adapter::ProjectionTablesHook)
  end

  it 'mantém o alvo F5 intacto mesmo com a flag ligada' do
    ENV[described_class::FLAG] = '1'
    ENV[described_class::F5_ENV_KEY] = described_class::F5_RUNNER
    reset_to_g0!

    expect(described_class.install!).to be(false)

    Connecta::Runtime::G0Adapter::TABLES.each_value do |product|
      model = Connecta::Runtime::G0Adapter::TABLES.key(product)
      expect(model.table_name).to eq(g0_name(product)), "#{model} não deveria ser retargetado no F5"
    end
  end

  it 'falha alto quando uma tabela de produto está ausente, sem mockar ou pular' do
    ENV[described_class::FLAG] = '1'
    ENV.delete(described_class::F5_ENV_KEY)
    reset_to_g0!
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:data_source_exists?).and_wrap_original do |original, table|
      next false if table == 'connecta_scoped_inboxes'

      original.call(table)
    end

    expect { described_class.install! }.to raise_error(RuntimeError, /missing product tables.*connecta_scoped_inboxes/)
  end

  it 'a fonte de produção Projection.marked? propaga erro em vez de devolver unmarked (fail-closed)' do
    allow(Connecta::Scope::ScopedInbox).to receive(:exists?).and_raise(ActiveRecord::StatementInvalid.new('db down (injetado)'))

    expect { Connecta::Scope::Projection.marked?(1) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'a fonte de produção Projection não tem fail-open com rescue falso' do
    source = File.read(Rails.root.join('app/services/connecta/scope/projection.rb'))

    expect(source).not_to match(/rescue.*false/m)
  end
end
