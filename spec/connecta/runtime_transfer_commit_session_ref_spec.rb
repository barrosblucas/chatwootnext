require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Contrato de fio v1 §9.4: o job de commit consome `to_session_ref` da resposta
# do commit e o persiste no registro ANTES de copiar para o escopo destino. O
# prepare nunca pode fornecê-lo (a sessão destino ainda não existe). Replay
# idempotente devolve a mesma referência (sem recobrir); resposta sem o campo
# falha fechado em vez de gravar nil silencioso.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
# Scope aponta às tabelas de produto (mesmo mapa de G0Adapter::TABLES; ver support/g0_product_tables.rb).
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · commit consome to_session_ref (§9.4)' do # rubocop:disable RSpec/DescribeClass
  include_context 'with connecta g0 scope fixture'

  let(:commit_response) { { 'case_version' => 2, 'to_session_ref' => 'sess-165' } }
  let(:sent) { [] }
  let(:client) do
    recipient = sent
    response = commit_response
    stub = Object.new
    stub.define_singleton_method(:post) do |path, payload|
      recipient << { method: :post, path: path, payload: payload }
      path.end_with?('/commit') ? response : {}
    end
    stub
  end

  before do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s, 'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
  end

  # Estado que o commit local (LocalTransaction#commit_local!) deixa antes do job
  # (mesma montagem do contrato Fork→WP itens 3 e 5): origem transferred_out e
  # destino pending_activation versão 0 no inbox/contato da origem. O prepare real
  # nunca preenche platform_session_ref (WP ainda não criou a sessão destino).
  def prepare_committed_local!(session_ref:)
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'transferred_out')
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_b.id)
                                      .update!(state: 'pending_activation', case_version: 0, org_unit: org_b,
                                               contact_id: contact_a.id)
    transfer = Connecta::Transfer::TransferRecord.create!(
      source_conversation_id: conv_a.id, state: 'committed_local',
      destination_conversation_id: conv_b.id, destination_org_unit_id: org_b.id,
      target_case_version: 2, platform_session_ref: session_ref
    )
    outbox = instance_double(Connecta::Outbox)
    allow(Connecta::Outbox).to receive(:find_by!).and_return(outbox)
    allow(Connecta::Outbox).to receive(:find_by).and_return(outbox)
    allow(outbox).to receive(:update!)
    transfer
  end

  it 'primeira resposta do commit persiste o ref no registro' do
    transfer = prepare_committed_local!(session_ref: nil)

    Connecta::Runtime::TransferCommitJob.perform_now(transfer.id)

    expect(transfer.reload.platform_session_ref).to eq('sess-165')
  end

  it 'escopo destino recebe o ref após o passo de commit do job' do
    transfer = prepare_committed_local!(session_ref: nil)

    Connecta::Runtime::TransferCommitJob.perform_now(transfer.id)

    destination = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_b.id)
    expect(destination.platform_session_ref).to eq('sess-165')
    expect(destination.state).to eq('active')
  end

  it 'replay idempotente devolve o mesmo ref e não recobre o gravado' do
    transfer = prepare_committed_local!(session_ref: 'sess-165')

    Connecta::Runtime::TransferCommitJob.perform_now(transfer.id)

    expect(transfer.reload.platform_session_ref).to eq('sess-165')
    destination = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_b.id)
    expect(destination.platform_session_ref).to eq('sess-165')
    commit = sent.find { |entry| entry[:path] == "/attendance/v1/transfers/#{transfer.id}/commit" }
    expect(commit).not_to be_nil
  end

  context 'resposta do commit sem to_session_ref' do
    let(:commit_response) { { 'case_version' => 2 } }

    it 'falha fechado com erro tipado e não grava nil' do
      transfer = prepare_committed_local!(session_ref: nil)

      expect do
        Connecta::Runtime::TransferCommitJob.perform_now(transfer.id)
      end.to raise_error(Connecta::Runtime::TransferCommitJob::InvalidCommitResponse)

      expect(transfer.reload.platform_session_ref).to be_nil
      expect(transfer.reload.state).to eq('committed_local')
      destination = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_b.id)
      expect(destination.platform_session_ref).to be_nil
    end

    it 'ref em branco também falha fechado' do
      transfer = prepare_committed_local!(session_ref: nil)
      blank_client = Object.new
      blank_client.define_singleton_method(:post) do |_path, _payload|
        { 'case_version' => 2, 'to_session_ref' => '  ' }
      end
      allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(blank_client)

      expect do
        Connecta::Runtime::TransferCommitJob.perform_now(transfer.id)
      end.to raise_error(Connecta::Runtime::TransferCommitJob::InvalidCommitResponse)

      expect(transfer.reload.platform_session_ref).to be_nil
    end
  end
end
