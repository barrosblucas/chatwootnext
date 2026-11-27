require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Atribuição cross-unit: gestor/admin move a conversa de setor pelo mesmo
# TransferTransaction da transferência normal e o responsável é atribuído na
# conversa destino. Transporte e jobs são doubles de fronteira; o SUT (policy,
# transação, registros e Outbox) é real.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::G0ProductTables.install!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta · atribuição com mudança de setor (cross-unit)', type: :request do
  include ActiveJob::TestHelper

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

  include_context 'with connecta g0 scope fixture'

  let!(:beatriz) { create(:user, account: account, role: :agent, name: 'beatriz luz') }
  let!(:carlos) { create(:user, account: account, role: :agent, name: 'Carlos Mendes') }
  let!(:diana) { create(:user, account: account, role: :agent, name: 'Diana Dupla') }
  let!(:native_admin) { create(:user, account: account, role: :administrator, name: 'Admin Nativo') }

  let(:sent) { [] }
  let(:client) do
    recipient = sent
    stub = Object.new
    stub.define_singleton_method(:post) do |path, payload|
      recipient << { path: path, payload: payload }
      { 'case_version' => 1, 'to_session_ref' => 'sess-assign-2' }
    end
    stub
  end

  def assignments_path(conversation)
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments"
  end

  before do
    [beatriz, diana].each do |user|
      Connecta::Scope::UserGrant.create!(user_id: user.id, org_unit_id: org_a.id, permission: 'atender')
    end
    [carlos, diana].each do |user|
      Connecta::Scope::UserGrant.create!(user_id: user.id, org_unit_id: org_b.id, permission: 'atender')
    end
    [beatriz, carlos, diana].each do |user|
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit_id: org_a.id, permission: 'gerir')
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit_id: org_b.id, permission: 'gerir')
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit_id: org_a.id, permission: 'transferir')
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s, 'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(Connecta::Runtime::TransferCommitJob).to receive(:perform_later)
    allow(Connecta::Runtime::TransferAbortJob).to receive(:perform_later)
  end

  it 'gestor atribui dentro do setor sem mover (AC5, mesma unidade)' do
    post assignments_path(conv_a), params: { assignee_id: beatriz.id }, headers: manager_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(conv_a.reload.assignee_id).to eq(beatriz.id)
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: conv_a.id).org_unit_id).to eq(org_a.id)
  end

  it 'gestor move para outro setor e atribui o alvo na conversa destino (AC5, AC6)' do
    post assignments_path(conv_a),
         params: { assignee_id: carlos.id, connecta_org_unit_id: org_b.id },
         headers: manager_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['id']).to eq(carlos.id)
    expect(conv_a.reload.assignee_id).to be_nil
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: conv_a.id).state).to eq('transferred_out')
    record = Connecta::Transfer::TransferRecord.find_by!(source_conversation_id: conv_a.id)
    destination = Conversation.find(record.destination_conversation_id)
    expect(destination.assignee_id).to eq(carlos.id)
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: destination.id).org_unit_id).to eq(org_b.id)
  end

  it 'move propaga para a plataforma como transferência normal (Outbox + job + prepare)' do
    post assignments_path(conv_a),
         params: { assignee_id: carlos.id, connecta_org_unit_id: org_b.id },
         headers: manager_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    record = Connecta::Transfer::TransferRecord.find_by!(source_conversation_id: conv_a.id)
    expect(Connecta::Outbox.find_by(dedupe_key: "transfer.committed:#{record.id}")).to be_present
    expect(Connecta::Runtime::TransferCommitJob).to have_received(:perform_later).with(kind_of(String))
    expect(sent.first[:path]).to eq('/attendance/v1/transfers/prepare')
  end

  it 'admin nativo move e atribui (AC6)' do
    post assignments_path(conv_a),
         params: { assignee_id: diana.id, connecta_org_unit_id: org_b.id },
         headers: native_admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    record = Connecta::Transfer::TransferRecord.find_by!(source_conversation_id: conv_a.id)
    expect(Conversation.find(record.destination_conversation_id).assignee_id).to eq(diana.id)
  end

  it 'atendente sem gerir recebe 403 e nada muda (AC6)' do
    post assignments_path(conv_a),
         params: { assignee_id: beatriz.id, connecta_org_unit_id: org_b.id },
         headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
    expect(conv_a.reload.assignee_id).to be_nil
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: conv_a.id).attributes.slice('state', 'org_unit_id'))
      .to eq({ 'state' => 'active', 'org_unit_id' => org_a.id })
    expect(Connecta::Transfer::TransferRecord.where(source_conversation_id: conv_a.id).count).to eq(0)
  end

  it 'alvo sem atender no destino recebe 403 (AC6)' do
    post assignments_path(conv_a),
         params: { assignee_id: beatriz.id, connecta_org_unit_id: org_b.id },
         headers: manager_a.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
    expect(Connecta::Transfer::TransferRecord.where(source_conversation_id: conv_a.id).count).to eq(0)
  end

  it 'unidade desconhecida responde 422 sem mover' do
    post assignments_path(conv_a),
         params: { assignee_id: carlos.id, connecta_org_unit_id: SecureRandom.uuid },
         headers: manager_a.create_new_auth_token

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: conv_a.id).state).to eq('active')
  end
end
