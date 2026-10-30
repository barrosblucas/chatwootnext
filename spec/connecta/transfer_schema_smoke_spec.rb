require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_transfer_schema'

# T0.7 (spike G0): schema de transferência e de despacho de saída. Prova o helper create-only, os índices únicos reais do banco
# e a validação de estado dos registros do spike. Nada é mockado. Valores aleatórios por execução, como no T0.3.
Connecta::G0TransferSchema.ensure!

RSpec.describe 'Connecta G0 · schema de transferência e despacho (T0.7)' do # rubocop:disable RSpec/DescribeClass
  let(:source_conversation_id) { SecureRandom.random_number(10**9) }
  let(:conversation_id) { SecureRandom.random_number(10**9) }
  let(:message_id) { SecureRandom.random_number(10**9) }
  let(:transfer_attributes) { { source_conversation_id: source_conversation_id, destination_org_unit_id: 2, state: 'requested' } }
  let(:dispatch_attributes) { { message_id: message_id, conversation_id: conversation_id, state: 'queued' } }

  # G0Adapter.install! (chamado por outros specs no mesmo processo) reatribui table_name às tabelas de produto e vaza entre exemplos.
  # Este spec testa o schema G0: fixa as tabelas G0 durante cada exemplo e restaura o mapeamento anterior ao final.
  around do |example|
    g0_tables = { Connecta::Transfer::TransferRecord => 'connecta_g0_transfers',
                  Connecta::Transfer::OutboundDispatchRecord => 'connecta_g0_outbound_dispatches' }
    previous = g0_tables.keys.index_with(&:table_name)
    g0_tables.each { |model, table| model.table_name = table }
    begin
      example.run
    ensure
      previous.each { |model, table| model.table_name = table }
    end
  end

  it 'ensure! é idempotente e deixa as duas tabelas criadas' do
    expect { 2.times { Connecta::G0TransferSchema.ensure! } }.not_to raise_error
    expect(ActiveRecord::Base.connection.tables).to include('connecta_g0_transfers', 'connecta_g0_outbound_dispatches')
  end

  it 'índice parcial aceita transfer fechado e barra segundo transfer aberto da mesma origem' do
    Connecta::Transfer::TransferRecord.create!(transfer_attributes.merge(state: 'aborted'))
    Connecta::Transfer::TransferRecord.create!(transfer_attributes.merge(state: 'requested'))

    expect do
      Connecta::Transfer::TransferRecord.transaction(requires_new: true) do
        Connecta::Transfer::TransferRecord.create!(transfer_attributes.merge(state: 'prepared', destination_org_unit_id: 3))
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'índice único barra segundo despacho para a mesma mensagem' do
    Connecta::Transfer::OutboundDispatchRecord.create!(dispatch_attributes)

    expect do
      Connecta::Transfer::OutboundDispatchRecord.transaction(requires_new: true) do
        Connecta::Transfer::OutboundDispatchRecord.create!(dispatch_attributes.merge(state: 'dispatching'))
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'modelos aceitam todo estado da lista e recusam estado fora dela' do
    Connecta::Transfer::TransferRecord::STATES.each do |state|
      expect(Connecta::Transfer::TransferRecord.new(transfer_attributes.merge(state: state))).to be_valid
    end
    Connecta::Transfer::OutboundDispatchRecord::STATES.each do |state|
      expect(Connecta::Transfer::OutboundDispatchRecord.new(dispatch_attributes.merge(state: state))).to be_valid
    end

    expect(Connecta::Transfer::TransferRecord.new(transfer_attributes.merge(state: 'bogus'))).not_to be_valid
    expect(Connecta::Transfer::OutboundDispatchRecord.new(dispatch_attributes.merge(state: 'bogus'))).not_to be_valid
  end
end
