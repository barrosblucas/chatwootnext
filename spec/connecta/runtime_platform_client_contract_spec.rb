require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Contrato de fio v1, itens 1–7 (Fork→WP): todas as chamadas carregam account_id
# (inteiro). Destinos leva actor_chatwoot_user_id; prepare leva protocolo/versão,
# destino, ator, hash e tamanho do resumo; commit leva destination_conversation_id
# (display_id) + committed_at (ISO8601); activated leva case_version; falha local
# pós-prepare chama abort via job com retry. Sem rede: PlatformClient dobrado;
# as expectativas afirmam paths e corpos exatos.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
# Scope aponta às tabelas de produto (mesmo mapa de G0Adapter::TABLES; ver support/g0_product_tables.rb).
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · contrato Fork para WP (itens 1-7)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:sent) { [] }
  let(:client) do
    recipient = sent
    stub = Object.new
    stub.define_singleton_method(:get) do |path|
      recipient << { method: :get, path: path }
      { 'destinations' => [] }
    end
    stub.define_singleton_method(:post) do |path, payload|
      recipient << { method: :post, path: path, payload: payload }
      { 'case_version' => 2, 'to_session_ref' => 'sess-2' }
    end
    stub
  end
  let(:summary) { { 'subject' => 'Segunda via', 'completed' => 'Dados conferidos', 'next_action' => 'Retorno do setor B' } }

  before do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s, 'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(Connecta::Runtime::TransferCommitJob).to receive(:perform_later)
    allow(Connecta::Runtime::TransferAbortJob).to receive(:perform_later)
    Connecta::UserGrant.create!(user_id: agent_a.id, org_unit_id: org_a.id, permission: 'transferir')
  end

  it 'item 1: destinos usa display_id + account_id + actor_chatwoot_user_id' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/connecta_transfer/destinations",
        headers: agent_a.create_new_auth_token

    call = sent.find { |entry| entry[:path].to_s.start_with?('/attendance/v1/transfer-destinations') }
    expect(call).not_to be_nil
    query = URI.decode_www_form(URI(call[:path]).query.to_s).to_h
    expect(query['account_id']).to eq(account.id.to_s)
    expect(query['conversation_id']).to eq(conv_a.display_id.to_s)
    expect(query['actor_chatwoot_user_id']).to eq(agent_a.id.to_s)
  end

  it 'item 2: prepare carrega account_id, protocolo, versao, destino, ator, hash e tamanho' do
    Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    ).call

    prepare = sent.find { |entry| entry[:path] == '/attendance/v1/transfers/prepare' }
    expect(prepare[:payload]).to include(
      account_id: account.id, conversation_id: conv_a.display_id,
      case_protocol: 'CASO-A', case_version: 1,
      destination_org_unit_id: org_b.id.to_s, actor_chatwoot_user_id: agent_a.id
    )
    expect(prepare[:payload][:summary_sha256]).to match(/\A[0-9a-f]{64}\z/)
    expect(prepare[:payload][:summary_length]).to be > 0
  end

  it 'itens 3 e 5: commit leva account_id + committed_at; activated leva account_id + case_version' do
    # Estado que o commit local (LocalTransaction#commit_local!) deixa antes do job: origem transferred_out e
    # destino pending_activation com versão 0, no mesmo inbox/contato da origem (open_destination). O índice parcial
    # de (inbox, contato) só admite um scope não terminal, por isso a origem já saiu dos estados não terminais.
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'transferred_out')
    # O scope do destino já existe (ReceptionScopeCreator no after_create da conversa); só o estado muda.
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_b.id)
                                      .update!(state: 'pending_activation', case_version: 0, org_unit: org_b, contact_id: contact_a.id)
    transfer = Connecta::Transfer::TransferRecord.create!(
      source_conversation_id: conv_a.id, state: 'committed_local',
      destination_conversation_id: conv_b.id, destination_org_unit_id: org_b.id,
      target_case_version: 2, platform_session_ref: 'sess-2'
    )
    outbox = instance_double(Connecta::Outbox)
    allow(Connecta::Outbox).to receive(:find_by!).and_return(outbox)
    allow(Connecta::Outbox).to receive(:find_by).and_return(outbox)
    allow(outbox).to receive(:update!)

    Connecta::Runtime::TransferCommitJob.perform_now(transfer.id)

    commit = sent.find { |entry| entry[:path] == "/attendance/v1/transfers/#{transfer.id}/commit" }
    activated = sent.find { |entry| entry[:path] == "/attendance/v1/transfers/#{transfer.id}/activated" }
    expect(commit[:payload]).to include(account_id: account.id, destination_conversation_id: conv_b.display_id)
    expect(commit[:payload][:committed_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    expect(activated[:payload]).to include(account_id: account.id, case_version: 2)
  end

  it 'item 4: falha local apos prepare chama abort via job com retry' do
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
    expect(Connecta::Runtime::TransferAbortJob).to have_received(:perform_later).with(record.id, 'local_failure')
  end

  it 'item 6: identity-links confirm carrega account_id' do
    post "/api/v1/accounts/#{account.id}/connecta/identity_link",
         params: { code: 'ABC123' }, headers: agent_a.create_new_auth_token

    confirm = sent.find { |entry| entry[:path] == '/attendance/v1/identity-links/confirm' }
    expect(confirm[:payload]).to include(account_id: account.id, chatwoot_user_id: agent_a.id, code: 'ABC123')
  end

  it 'item 7: emergency-revocations carrega account_id' do
    revocation_id = SecureRandom.uuid
    Connecta::Outbox.create!(
      dedupe_key: "acl.emergency-revocation:#{agent_b.id}:2", event_type: 'acl.emergency-revocation',
      payload: { user_id: agent_b.id, actor_user_id: agent_a.id, epoch: 2, revocation_id: revocation_id }
    )

    Connecta::Runtime::EmergencyRevocationJob.perform_now(agent_b.id, agent_a.id, 2, revocation_id)

    emergency = sent.find { |entry| entry[:path] == '/attendance/v1/acl/emergency-revocations' }
    expect(emergency[:payload]).to include(account_id: account.id, chatwoot_user_id: agent_b.id,
                                           actor_user_id: agent_a.id, epoch: 2)
  end

  it 'abort job registra retry para PlatformClient::Error igual aos demais jobs' do
    # ActiveJob 7.1 não expõe retry_on_list; retry_on vira rescue_handler (chave = nome da classe).
    # wait/attempts ficam no closure do Rails e não são inspecionáveis aqui; a checagem prova só o registro.
    [Connecta::Runtime::TransferAbortJob, Connecta::Runtime::TransferCommitJob, Connecta::Runtime::EmergencyRevocationJob].each do |job|
      expect(job.rescue_handlers.map(&:first)).to include('Connecta::Runtime::PlatformClient::Error')
    end
  end
end
