require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Transação runtime prepare→commit→activated: prepare carrega account_id; falha
# local após prepare bem-sucedido enfileira o job de abort (contrato v1 §4, retry
# igual aos demais); erro de transporte vira estado unknown sem abort remoto.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
# Scope aponta às tabelas de produto (mesmo mapa de G0Adapter::TABLES; ver support/g0_product_tables.rb).
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · transação prepare→commit→activated' do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper
  include_context 'with connecta g0 scope fixture'

  let(:sent) { [] }
  let(:client) do
    recipient = sent
    stub = Object.new
    stub.define_singleton_method(:post) do |path, payload|
      recipient << { method: :post, path: path, payload: payload }
      { 'case_version' => 1, 'to_session_ref' => 'sess-2' }
    end
    stub
  end
  let(:summary) { { 'subject' => 'Segunda via', 'completed' => 'Dados conferidos', 'next_action' => 'Retorno do setor B' } }

  before do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s, 'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                                     'CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(Connecta::Runtime::TransferCommitJob).to receive(:perform_later)
    allow(Connecta::Runtime::TransferAbortJob).to receive(:perform_later)
    Connecta::UserGrant.create!(user_id: agent_a.id, org_unit_id: org_a.id, permission: 'transferir')
  end

  it 'prepare→commit local enfileira o commit e retorna pending_activation' do
    result = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    ).call

    expect(result[:status]).to eq('pending_activation')
    prepare = sent.find { |entry| entry[:path] == '/attendance/v1/transfers/prepare' }
    expect(prepare[:payload]).to include(account_id: account.id)
    expect(Connecta::Runtime::TransferCommitJob).to have_received(:perform_later).with(kind_of(String))
    expect(Connecta::Transfer::TransferRecord.where(source_conversation_id: conv_a.id).count).to eq(1)
  end

  it 'falha local apos prepare bem-sucedido enfileira abort e desfaz o preparo' do
    transaction = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    )
    local = instance_double(Connecta::Transfer::LocalTransaction)
    record = Connecta::Transfer::TransferRecord.create!(
      source_conversation_id: conv_a.id, state: 'awaiting_dispatch',
      destination_org_unit_id: org_b.id
    )
    allow(Connecta::Transfer::LocalTransaction).to receive(:new).and_return(local)
    allow(local).to receive(:begin!).and_return(:proceed)
    allow(local).to receive(:record).and_return(record)
    allow(local).to receive(:commit_local!).and_raise(ActiveRecord::RecordNotFound, 'preparo local ausente')
    allow(local).to receive(:abort!)

    expect { transaction.call }.to raise_error(Connecta::Runtime::TransferTransaction::Error)
    expect(local).to have_received(:abort!)
    expect(Connecta::Runtime::TransferAbortJob).to have_received(:perform_later).with(record.id, 'local_failure')
  end

  it 'falha antes do prepare (RecordNotFound) vira erro de domínio, sem NoMethodError' do
    allow(Connecta::Scope::OrgUnit).to receive(:find_by).and_raise(ActiveRecord::RecordNotFound, 'unidade ausente')
    transaction = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    )

    expect { transaction.call }.to raise_error(Connecta::Runtime::TransferTransaction::Error, 'unidade ausente') { |error|
      expect(error.status).to eq(:conflict)
    }
    expect(sent).to be_empty
    expect(Connecta::Runtime::TransferAbortJob).not_to have_received(:perform_later)
  end

  it 'falha antes do prepare (ArgumentError) vira erro de domínio, sem NoMethodError' do
    allow(Connecta::Transfer::LocalTransaction).to receive(:new).and_raise(ArgumentError, 'payload inválido')
    transaction = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    )

    expect { transaction.call }.to raise_error(Connecta::Runtime::TransferTransaction::Error, 'payload inválido') { |error|
      expect(error.status).to eq(:unprocessable_entity)
    }
    expect(sent).to be_empty
    expect(Connecta::Runtime::TransferAbortJob).not_to have_received(:perform_later)
  end

  it 'erro de transporte no prepare marca unknown sem abort remoto' do
    failing = Object.new
    failing.define_singleton_method(:post) do |_path, _payload|
      raise Connecta::Runtime::PlatformClient::Error.new('timeout', status: :gateway_timeout)
    end
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(failing)

    transaction = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    )

    expect { transaction.call }.to raise_error(Connecta::Runtime::TransferTransaction::Error)
    expect(Connecta::Runtime::TransferAbortJob).not_to have_received(:perform_later)
    record = Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conv_a.id)
    expect(record&.state).to eq('unknown')
  end

  it 'prepare recusado pela plataforma desfaz o preparo sem abort remoto' do
    refusing = Object.new
    refusing.define_singleton_method(:post) do |_path, _payload|
      raise Connecta::Runtime::PlatformClient::Error.new('forbidden', status: :forbidden)
    end
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(refusing)

    transaction = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    )

    expect { transaction.call }.to raise_error(Connecta::Runtime::TransferTransaction::Error)
    expect(Connecta::Runtime::TransferAbortJob).not_to have_received(:perform_later)
  end

  it 'job de abort reenfileira com wait de 10s e desiste após 24 tentativas' do
    # Comportamento real via test adapter: falha de transporte no PlatformClient aciona retry_on.
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_raise(
      Connecta::Runtime::PlatformClient::Error.new('timeout', status: :gateway_timeout)
    )
    retrying = Connecta::Runtime::TransferAbortJob.new(1, 'local_failure')
    expect { retrying.perform_now }.not_to raise_error
    retried = enqueued_jobs.last
    expect(retried[:job]).to eq(Connecta::Runtime::TransferAbortJob)
    expect(retried[:at].to_f).to be_within(5).of(10.seconds.from_now.to_f)

    # 23 falhas anteriores no contador por exceção (chave = exceptions.to_s, como em ActiveJob::Exceptions#executions_for).
    # A 24ª execução atinge attempts: 24 e o erro sobe sem novo agendamento.
    exhausted = Connecta::Runtime::TransferAbortJob.new(1, 'local_failure')
    exhausted.exception_executions = { [Connecta::Runtime::PlatformClient::Error].to_s => 23 }
    expect { exhausted.perform_now }.to raise_error(Connecta::Runtime::PlatformClient::Error)
  end

  it 'jobs de commit, abort e revogação registram o mesmo handler de retry' do
    # Registro do handler (chave = nome da classe). Complementa o teste de comportamento acima, que cobre só o abort.
    # wait/attempts dos commit e revogação NÃO são verificados aqui; só o registro.
    %w[TransferAbortJob TransferCommitJob EmergencyRevocationJob].each do |job_name|
      handlers = Connecta::Runtime.const_get(job_name).rescue_handlers.map(&:first)
      expect(handlers).to include('Connecta::Runtime::PlatformClient::Error')
    end
  end
end
