require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Fork prepare: resposta de prepare ecoa a origem (source N → response N),
# alvo derivado é N+1; commit/activated exigem o alvo exato.
# Regressão N1 (500 porque o fork esperava response2 e o WP devolve source1):
# prepare recebe source1/response1 e deriva target2; source3/response3 deriva
# target4; replay idempotente (mesmo transfer_id, mesma origem) devolve a origem.
# Resposta bem-sucedida mas malformada (ausente/não-numérica/divergente) é 502
# com compensação da reserva potencial (abort local + job remoto com o ID exato),
# nunca unknown; transporte incerto preserva unknown sem abort remoto; registros
# committed_local/committed/activation_stuck nunca são desfeitos.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · versão de prepare ecoa origem, alvo=origem+1' do # rubocop:disable RSpec/DescribeClass
  include_context 'with connecta g0 scope fixture'

  let(:sent) { [] }
  let(:prepare_responses) { [{ 'case_version' => 1, 'to_session_ref' => 'sess-2' }] }
  let(:client) do
    recipient = sent
    queue = prepare_responses
    stub = Object.new
    stub.define_singleton_method(:post) do |path, payload|
      recipient << { method: :post, path: path, payload: payload }
      if path == '/attendance/v1/transfers/prepare'
        queue.shift || { 'case_version' => 1, 'to_session_ref' => 'sess-2' }
      else
        { 'case_version' => 2, 'to_session_ref' => 'sess-2' }
      end
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

  def run_transfer(conversation = conv_a)
    Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conversation, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    ).call
  end

  it 'sequência real: request1/response1 deriva target2; commit/activated exigem 2' do
    result = run_transfer

    expect(result[:status]).to eq('pending_activation')
    prepare = sent.find { |entry| entry[:path] == '/attendance/v1/transfers/prepare' }
    expect(prepare[:payload]).to include(case_version: 1)
    record = Connecta::Transfer::TransferRecord.find(result[:transfer_id])
    expect(record).to have_attributes(state: 'committed_local', target_case_version: 2, platform_session_ref: 'sess-2')
    expect(Connecta::Runtime::TransferCommitJob).to have_received(:perform_later).with(record.id)
  end

  it 'source3/response3 deriva target4' do
    origin = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)
    origin.update!(case_version: 3)
    recipient = sent
    v3_client = Object.new
    v3_client.define_singleton_method(:post) do |path, payload|
      recipient << { method: :post, path: path, payload: payload }
      path == '/attendance/v1/transfers/prepare' ? { 'case_version' => 3, 'to_session_ref' => 'sess-4' } : { 'case_version' => 4 }
    end
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(v3_client)

    result = run_transfer

    record = Connecta::Transfer::TransferRecord.find(result[:transfer_id])
    expect(record.target_case_version).to eq(4)
    expect(record.platform_session_ref).to eq('sess-4')
  end

  it 'replay idempotente devolve a versão de origem (mesmo transfer, mesma origem)' do
    replay_client = Object.new
    replay_client.define_singleton_method(:post) do |path, _payload|
      path == '/attendance/v1/transfers/prepare' ? { 'case_version' => 1, 'to_session_ref' => 'sess-2' } : { 'case_version' => 2 }
    end
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(replay_client)
    transaction = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    )
    source = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)
    precommit = Connecta::Transfer::TransferRecord.create!(
      source_conversation_id: conv_a.id, state: 'prepared', destination_org_unit_id: org_b.id
    )
    first_target = transaction.send(:prepare_remote!, precommit, source, 'hash', 10, { remote: false })
    second_target = transaction.send(:prepare_remote!, precommit.reload, source, 'hash', 10, { remote: false })
    expect(first_target).to eq(2)
    expect(second_target).to eq(2)
    expect(precommit.reload.target_case_version).to eq(2)
  end

  it 'versão ausente vira 502 com compensação no registro pré-commit exato' do
    failing = Object.new
    failing.define_singleton_method(:post) { |_path, _payload| {} }
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(failing)

    expect { run_transfer }.to raise_error(Connecta::Runtime::TransferTransaction::Error) { |error|
      expect(error.status).to eq(:bad_gateway)
      expect(error.message).to eq('Platform returned an invalid case version')
    }
    record = Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conv_a.id)
    expect(record&.state).to eq('aborted')
    expect(Connecta::Runtime::TransferAbortJob).to have_received(:perform_later).with(record.id, 'local_failure')
    expect(record.state).not_to eq('unknown')
  end

  it 'versão não-numérica vira 502 com compensação, sem expor payload' do
    failing = Object.new
    failing.define_singleton_method(:post) { |_path, _payload| { 'case_version' => 'dois' } }
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(failing)

    expect { run_transfer }.to raise_error(Connecta::Runtime::TransferTransaction::Error) { |error|
      expect(error.status).to eq(:bad_gateway)
      expect(error.message).not_to include('dois')
    }
    record = Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conv_a.id)
    expect(record&.state).to eq('aborted')
    expect(Connecta::Runtime::TransferAbortJob).to have_received(:perform_later).with(record.id, kind_of(String))
  end

  it 'versão divergente (2 quando a origem é 1) vira 502 com compensação' do
    failing = Object.new
    failing.define_singleton_method(:post) { |_path, _payload| { 'case_version' => 2, 'to_session_ref' => 'sess-x' } }
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(failing)

    expect { run_transfer }.to raise_error(Connecta::Runtime::TransferTransaction::Error) { |error|
      expect(error.status).to eq(:bad_gateway)
    }
    record = Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conv_a.id)
    expect(record&.state).to eq('aborted')
    expect(Connecta::Runtime::TransferAbortJob).to have_received(:perform_later).with(record.id, kind_of(String))
  end

  it 'limpeza pré-commit guarda identidade: abort após commit é recusado sem mudar nada nem abortar remoto' do
    run_transfer
    record = Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conv_a.id)
    expect(record.state).to eq('committed_local')
    origin = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)

    local = Connecta::Transfer::LocalTransaction.new(scope: origin, destination_org_unit: org_b)
    expect { local.abort! }.to raise_error(ActiveRecord::RecordNotFound)

    expect(record.reload.state).to eq('committed_local')
    expect(origin.reload.state).to eq('transferred_out')
    expect(Connecta::Runtime::TransferAbortJob).not_to have_received(:perform_later)
  end

  it 'transporte incerto preserva unknown sem abort remoto' do
    failing = Object.new
    failing.define_singleton_method(:post) do |_path, _payload|
      raise Connecta::Runtime::PlatformClient::Error.new('timeout', status: :gateway_timeout)
    end
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(failing)

    expect { run_transfer }.to raise_error(Connecta::Runtime::TransferTransaction::Error)
    expect(Connecta::Runtime::TransferAbortJob).not_to have_received(:perform_later)
    record = Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conv_a.id)
    expect(record&.state).to eq('unknown')
  end

  it 'erro de domínio expõe HTTP controlado sem payload (contrato do controller)' do
    failing = Object.new
    failing.define_singleton_method(:post) { |_path, _payload| { 'case_version' => 99 } }
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(failing)

    error = nil
    begin
      run_transfer
    rescue Connecta::Runtime::TransferTransaction::Error => e
      error = e
    end
    expect(error).not_to be_nil
    expect(error.status).to eq(:bad_gateway)
    expect([:bad_gateway, :conflict, :unprocessable_entity, :service_unavailable, :forbidden, :not_found]).to include(error.status)
  end
end
