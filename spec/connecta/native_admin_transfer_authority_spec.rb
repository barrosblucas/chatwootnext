require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# F2 (fork emite claim de autoridade só do servidor): AccountUser/NativeAdmin/Projection REAIS;
# só a fronteira HTTP (HTTParty, que usa Net::HTTP sob WebMock) é trocada. Nenhum stub de
# PlatformClient, NativeAdmin, Projection ou role.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::G0ProductTables.install!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta runtime · claim de autoridade do admin nativo (F2)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:claim) { 'chatwoot_account_admin' }
  let(:destinations_path) do
    "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/connecta_transfer/destinations"
  end
  let(:transfer_params) { { target_org_unit_id: org_b.id.to_s, summary: transfer_summary } }
  let(:transfer_path) { "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/connecta_transfer" }
  let(:transfer_summary) do
    { 'subject' => 'Assunto F2', 'completed' => 'Etapas concluidas', 'next_action' => 'Retorno do setor' }
  end
  let(:wire_platform) { 'http://platform.wiremock' }
  let(:wire_secret) { 'f2-synthetic-claim-secret' }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }

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

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => account.id.to_s,
                        'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                        'CONNECTA_PLATFORM_URL' => wire_platform,
                        'CONNECTA_FORK_TO_PLATFORM_SECRET' => wire_secret
                      ))
    create(:inbox_member, inbox: whatsapp_inbox, user: native_admin)
    Connecta::Scope::UserAuthEpoch.create!(user_id: native_admin.id, epoch: 1)
    Connecta::UserGrant.create!(user_id: agent_a.id, org_unit_id: org_a.id, permission: 'transferir')
    allow(Connecta::Runtime::TransferCommitJob).to receive(:perform_later)
    allow(Connecta::Runtime::TransferAbortJob).to receive(:perform_later)
    allow(ActionCable.server).to receive(:broadcast)
  end

  def last_request_matching(method, path_pattern)
    matched = nil
    expect(WebMock).to(have_requested(method, path_pattern).with { |request| matched = request })
    matched
  end

  def canonical_get_path(query)
    "/attendance/v1/transfer-destinations?#{URI.encode_www_form(
      { account_id: query['account_id'], conversation_id: query['conversation_id'],
        actor_chatwoot_user_id: query['actor_chatwoot_user_id'], actor_authority: query['actor_authority'] }
    )}"
  end

  def signature_valid?(request, method, path)
    signature = request.headers['X-Connecta-Signature'].to_s
    timestamp = request.headers['X-Connecta-Timestamp'].to_s
    canonical = [timestamp, method.to_s.upcase, path, request.body.to_s].join('.')
    signature == "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', wire_secret, canonical)}"
  end

  def stub_destinations
    stub_request(:get, %r{attendance/v1/transfer-destinations}o)
      .to_return(status: 200, body: { destinations: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_prepare
    stub_request(:post, "#{wire_platform}/attendance/v1/transfers/prepare")
      .to_return(status: 200, body: { 'case_version' => 1, 'to_session_ref' => 'sess-f2' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  it 'admin nativo sem grants: query e prepare contem o claim com assinatura HMAC valida' do
    stub_destinations
    stub_prepare

    get destinations_path, headers: native_admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    get_request = last_request_matching(:get, %r{attendance/v1/transfer-destinations}o)
    query = URI.decode_www_form(get_request.uri.query.to_s).to_h
    aggregate_failures 'claim do admin nativo na query' do
      expect(query.keys).to match_array(%w[account_id conversation_id actor_chatwoot_user_id actor_authority])
      expect(query['actor_authority']).to eq(claim)
      expect(signature_valid?(get_request, :get, canonical_get_path(query))).to be(true)
    end

    post transfer_path, params: transfer_params, headers: native_admin.create_new_auth_token
    expect(response).to have_http_status(:accepted)
    prepare_request = last_request_matching(:post, %r{attendance/v1/transfers/prepare}o)
    aggregate_failures 'claim do admin nativo no prepare' do
      expect(JSON.parse(prepare_request.body)['actor_authority']).to eq(claim)
      expect(signature_valid?(prepare_request, :post, '/attendance/v1/transfers/prepare')).to be(true)
    end
  end

  it 'agent com grants sinteticos: query e prepare vao sem claim' do
    stub_destinations
    stub_prepare

    get destinations_path, headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    query = URI.decode_www_form(last_request_matching(:get, %r{attendance/v1/transfer-destinations}o).uri.query.to_s).to_h
    expect(query).not_to have_key('actor_authority')

    post transfer_path, params: transfer_params, headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:accepted)
    prepare_request = last_request_matching(:post, %r{attendance/v1/transfers/prepare}o)
    expect(JSON.parse(prepare_request.body)).not_to have_key('actor_authority')
  end

  it 'nominal-only (projecao admin sem AccountUser administrator): sem claim e policy nega' do
    stub_destinations

    get destinations_path, headers: admin_nominal.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
    expect(WebMock).not_to have_requested(:get, %r{attendance/v1/transfer-destinations}o)

    expect do
      post transfer_path, params: transfer_params, headers: admin_nominal.create_new_auth_token
    end.not_to change(Connecta::Transfer::TransferRecord, :count)
    expect(response).not_to have_http_status(:accepted)
    expect(WebMock).not_to have_requested(:post, %r{attendance/v1/transfers/prepare}o)
  end

  it 'rebaixamento para agent com grants entre list e prepare recalcula fresh: prepare vai sem claim' do
    stub_destinations
    stub_prepare

    get destinations_path, headers: native_admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    query = URI.decode_www_form(last_request_matching(:get, %r{attendance/v1/transfer-destinations}o).uri.query.to_s).to_h
    expect(query['actor_authority']).to eq(claim)

    AccountUser.find_by!(account_id: account.id, user_id: native_admin.id).update!(role: :agent)
    Connecta::UserGrant.create!(user_id: native_admin.id, org_unit_id: org_a.id, permission: 'transferir')
    Connecta::UserGrant.create!(user_id: native_admin.id, org_unit_id: org_a.id, permission: 'atender')

    # create_new_auth_token fixa o role no token: reautentica após o rebaixamento.
    post transfer_path, params: transfer_params, headers: User.find(native_admin.id).create_new_auth_token
    expect(response).to have_http_status(:accepted)
    prepare_request = last_request_matching(:post, %r{attendance/v1/transfers/prepare}o)
    expect(JSON.parse(prepare_request.body)).not_to have_key('actor_authority')
  end

  it 'admin da conta A em conversa da conta B: mismatch nega sem claim elevado' do
    other_account = create(:account)
    other_channel = build(:channel_whatsapp, account: other_account, provider: 'baileys')
    other_channel.save!(validate: false)
    other_inbox = build(:inbox, account: other_account, channel: other_channel, name: 'Outra conta F2')
    other_inbox.save!(validate: false)
    other_contact = create(:contact, account: other_account)
    other_conversation = create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact)
    other_org = Connecta::Scope::OrgUnit.create!(name: 'Outra F2', path: '/outra-f2/')
    Connecta::Scope::ScopedInbox.create!(inbox_id: other_inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: other_conversation.id, inbox_id: other_inbox.id, contact_id: other_contact.id,
      org_unit: other_org, state: 'active', case_protocol: 'CASO-X', case_version: 1
    )

    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => other_account.id.to_s,
                        'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                        'CONNECTA_PLATFORM_URL' => wire_platform,
                        'CONNECTA_FORK_TO_PLATFORM_SECRET' => wire_secret
                      ))
    stub_destinations
    stub_prepare

    get "/api/v1/accounts/#{other_account.id}/conversations/#{other_conversation.display_id}/connecta_transfer/destinations",
        headers: native_admin.create_new_auth_token

    expect(response).not_to have_http_status(:ok)
    expect(WebMock).not_to have_requested(:get, %r{attendance/v1/transfer-destinations}o)
    mismatch = Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: other_conversation, actor: native_admin,
      destination_org_unit_id: other_org.id.to_s, summary: transfer_summary
    ).send(:native_authority)
    expect(mismatch).to be_nil
  end

  it 'param forjado actor_authority de um agent nao e repassado' do
    stub_destinations
    stub_prepare

    get "#{destinations_path}?actor_authority=#{claim}", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    query = URI.decode_www_form(last_request_matching(:get, %r{attendance/v1/transfer-destinations}o).uri.query.to_s).to_h
    expect(query).not_to have_key('actor_authority')

    post transfer_path,
         params: transfer_params.merge(actor_authority: claim),
         headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:accepted)
    prepare_request = last_request_matching(:post, %r{attendance/v1/transfers/prepare}o)
    expect(JSON.parse(prepare_request.body)).not_to have_key('actor_authority')
  end
end
