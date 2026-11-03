require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# I.1b-runtime (lacuna de prova): transferência via endpoint real + TransferTransaction de
# produto com tabelas PRODUTO do banco G0 sintético existente. Transporte PlatformClient e
# agendamento dos jobs são doubles de fronteira; o SUT (endpoint, policy, transação local,
# registros produto e Outbox/auditoria) é real. Produto = mesmo mapa de G0Adapter::TABLES.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::G0ProductTables.install!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta runtime · transferencia do admin nativo (I.1b-runtime)', type: :request do
  # G0Adapter.install! retargeta os modelos às tabelas de produto; outros specs do
  # processo podem remapear de volta às tabelas G0. Fixa produto durante cada exemplo
  # e restaura o mapeamento anterior ao final (como no transfer_schema_smoke_spec).
  around do |example|
    tables = Connecta::Runtime::G0Adapter::TABLES
    previous = tables.keys.index_with(&:table_name)
    tables.each { |model, table| model.table_name = table }
    Connecta::Runtime::G0Adapter.install!
    begin
      example.run
    ensure
      previous.each { |model, table| model.table_name = table }
    end
  end

  let!(:account) { create(:account) }
  let!(:channel) do
    build(:channel_whatsapp, account: account, provider: 'baileys').tap { |c| c.save!(validate: false) }
  end
  let!(:inbox) do
    build(:inbox, account: account, channel: channel, name: 'WhatsApp Runtime').tap { |i| i.save!(validate: false) }
  end
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let!(:org_root) { Connecta::Scope::OrgUnit.create!(name: 'Raiz', path: '/raiz/') }
  let!(:org_a) { Connecta::Scope::OrgUnit.create!(name: 'Setor A', path: '/raiz/a/', parent: org_root) }
  let!(:org_b) { Connecta::Scope::OrgUnit.create!(name: 'Setor B', path: '/raiz/b/', parent: org_root) }

  let(:sent) { [] }
  let(:client) do
    recipient = sent
    stub = Object.new
    stub.define_singleton_method(:post) do |path, payload|
      recipient << { path: path, payload: payload }
      { 'case_version' => 1, 'to_session_ref' => 'sess-runtime-2' }
    end
    stub
  end
  let(:summary) { { 'subject' => 'Segunda via', 'completed' => 'Dados conferidos', 'next_action' => 'Retorno do setor B' } }
  let(:transfer_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/connecta_transfer" }
  let(:transfer_params) { { target_org_unit_id: org_b.id.to_s, summary: summary } }

  before do
    Connecta::Scope::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current)
    Connecta::Scope::UserAuthEpoch.create!(user_id: native_admin.id, epoch: 1)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: inbox.id, contact_id: contact.id,
      org_unit: org_a, state: 'active', case_protocol: 'CASO-RUNTIME', case_version: 1
    )
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s, 'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(Connecta::Runtime::TransferCommitJob).to receive(:perform_later)
    allow(Connecta::Runtime::TransferAbortJob).to receive(:perform_later)
    allow(ActionCable.server).to receive(:broadcast)
  end

  it 'admin nativo sem grant transfere A→B pelo endpoint real com efeitos de produto' do
    post transfer_path, params: transfer_params, headers: native_admin.create_new_auth_token

    expect(response).to have_http_status(:accepted)
    body = JSON.parse(response.body)
    expect(body['status']).to eq('pending_activation')

    record = Connecta::Transfer::TransferRecord.find(body['transfer_id'])
    aggregate_failures 'efeitos de produto da transferencia nativa' do
      expect(record).to have_attributes(
        source_conversation_id: conversation.id, state: 'committed_local',
        destination_org_unit_id: org_b.id, summary_length: summary.to_json.bytesize,
        platform_session_ref: 'sess-runtime-2'
      )
      expect(record.prepared_at).not_to be_nil

      destination_scope = Connecta::Scope::ConversationScope.find_by!(transfer_id: record.id)
      expect(destination_scope).to have_attributes(
        inbox_id: inbox.id, contact_id: contact.id, org_unit_id: org_b.id,
        state: 'pending_activation', platform_session_ref: 'sess-runtime-2'
      )
      expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conversation.id).state).to eq('transferred_out')
      expect(Connecta::Outbox.find_by!(dedupe_key: "transfer.committed:#{record.id}"))
        .to have_attributes(event_type: 'transfer.committed', status: 'pending')
      expect(Connecta::Runtime::TransferCommitJob).to have_received(:perform_later).with(record.id)
    end
  end

  it 'destino de outra conta nega sem efeitos' do
    other_account = create(:account)
    other_channel = build(:channel_whatsapp, account: other_account, provider: 'baileys')
    other_channel.save!(validate: false)
    other_inbox = build(:inbox, account: other_account, channel: other_channel, name: 'Outra conta')
    other_inbox.save!(validate: false)
    other_contact = create(:contact, account: other_account)
    other_conversation = create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact)
    other_org = Connecta::Scope::OrgUnit.create!(name: 'Outra', path: '/outra/')
    Connecta::Scope::ScopedInbox.create!(inbox_id: other_inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: other_conversation.id, inbox_id: other_inbox.id, contact_id: other_contact.id,
      org_unit: other_org, state: 'active', case_protocol: 'CASO-X', case_version: 1
    )
    other_path = "/api/v1/accounts/#{other_account.id}/conversations/#{other_conversation.display_id}/connecta_transfer"

    post other_path,
         params: { target_org_unit_id: other_org.id.to_s, summary: summary },
         headers: native_admin.create_new_auth_token

    expect(response).not_to have_http_status(:accepted)
    expect(sent).to be_empty
    expect(Connecta::Transfer::TransferRecord.find_by(source_conversation_id: other_conversation.id)).to be_nil
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: other_conversation.id).state).to eq('active')
    expect(Connecta::Runtime::TransferCommitJob).not_to have_received(:perform_later)
  end

  it 'destino invalido nega sem efeitos' do
    post transfer_path,
         params: { target_org_unit_id: '00000000-0000-0000-0000-000000000000', summary: summary },
         headers: native_admin.create_new_auth_token

    expect(response).not_to have_http_status(:accepted)
    expect(sent).to be_empty
    expect(Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conversation.id)).to be_nil
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conversation.id).state).to eq('active')
    expect(Connecta::Runtime::TransferCommitJob).not_to have_received(:perform_later)
  end

  it 'mesma unidade de origem nega sem efeitos' do
    post transfer_path,
         params: { target_org_unit_id: org_a.id.to_s, summary: summary },
         headers: native_admin.create_new_auth_token

    expect(response).not_to have_http_status(:accepted)
    expect(sent).to be_empty
    expect(Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conversation.id)).to be_nil
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conversation.id).state).to eq('active')
  end

  it 'rebaixamento para agent tira a transferencia na mesma sessao' do
    post transfer_path, params: transfer_params, headers: native_admin.create_new_auth_token
    expect(response).to have_http_status(:accepted)

    transfer_id = JSON.parse(response.body)['transfer_id']
    destination_id = Connecta::Transfer::TransferRecord.find(transfer_id).destination_conversation_id
    AccountUser.find_by!(account_id: account.id, user_id: native_admin.id).update!(role: :agent)

    post transfer_path, params: transfer_params, headers: native_admin.create_new_auth_token

    expect(response).not_to have_http_status(:accepted)
    denied_records = Connecta::Transfer::TransferRecord.where(source_conversation_id: [conversation.id, destination_id])
    expect(denied_records.count).to eq(1)
    expect(Connecta::Transfer::TransferRecord.find_by(source_conversation_id: destination_id)).to be_nil
  end

  it 'agent sem grant transferir nega sem efeitos' do
    agent = create(:user, account: account, role: :agent)
    Connecta::Scope::UserAuthEpoch.create!(user_id: agent.id, epoch: 1)

    post transfer_path, params: transfer_params, headers: agent.create_new_auth_token

    expect(response).not_to have_http_status(:accepted)
    expect(sent).to be_empty
    expect(Connecta::Transfer::TransferRecord.find_by(source_conversation_id: conversation.id)).to be_nil
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conversation.id).state).to eq('active')
  end
end
