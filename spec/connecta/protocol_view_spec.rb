require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_product_tables'

# Produto: as tabelas connecta_* têm os mesmos nomes/colunas do runtime. O
# G0ProductTables aplica o mapa de produção e os hooks de projeção/query.
Connecta::G0ProductTables.install!
Connecta::Scope::Installer.install!

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe 'Connecta · protocolo, metadados e busca', type: :request do
  def body_json
    JSON.parse(response.body)
  end

  let!(:protocol) { "PROT#{SecureRandom.hex(4).upcase}" }
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, name: 'Caixa protocolo') }
  let!(:control_inbox) { create(:inbox, account: account, name: 'Caixa controle') }
  let!(:root_unit) { Connecta::Scope::OrgUnit.create!(name: 'Raiz', path: "/raiz-#{SecureRandom.hex(3)}/") }
  let!(:org_a) { Connecta::Scope::OrgUnit.create!(name: 'Setor A', path: "#{root_unit.path}a/", parent: root_unit) }
  let!(:org_b) { Connecta::Scope::OrgUnit.create!(name: 'Setor B', path: "#{root_unit.path}b/", parent: root_unit) }
  let!(:agent_a) { create(:user, account: account, role: :agent) }
  let!(:agent_b) { create(:user, account: account, role: :agent) }
  let!(:admin_nominal) { create(:user, account: account, role: :agent) }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let!(:transfer_only) { create(:user, account: account, role: :agent) }
  let!(:contact_a) { create(:contact, account: account) }
  let!(:contact_b) { create(:contact, account: account) }
  let!(:contact_origin) { create(:contact, account: account) }
  let!(:contact_control) { create(:contact, account: account) }
  let!(:conv_a) { create(:conversation, account: account, inbox: inbox, contact: contact_a, assignee: agent_a) }
  let!(:conv_b) { create(:conversation, account: account, inbox: inbox, contact: contact_b, assignee: agent_b) }
  let!(:origin_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact_origin, assignee: agent_a) }
  let!(:conv_control) { create(:conversation, account: account, inbox: control_inbox, contact: contact_control) }
  let!(:other_account) { create(:account) }
  let!(:other_inbox) { create(:inbox, account: other_account, name: 'Outra conta') }
  let!(:other_contact) { create(:contact, account: other_account) }
  let!(:other_org) { Connecta::Scope::OrgUnit.create!(name: 'Outra raiz', path: "/outra-#{SecureRandom.hex(3)}/") }
  let!(:other_conversation) do
    create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact).tap do |conversation|
      conversation.update!(display_id: 999_999)
    end
  end

  let(:protocol_path) { "/api/v1/accounts/#{account.id}/connecta/protocols/#{protocol}" }
  let(:metadata_path) { "/api/v1/accounts/#{account.id}/connecta/conversations/metadata" }
  let(:conversations_path) { "/api/v1/accounts/#{account.id}/conversations" }
  let(:search_path) { "/api/v1/accounts/#{account.id}/search" }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_native) { native_admin.create_new_auth_token }
  let(:token_admin_nominal) { admin_nominal.create_new_auth_token }
  let(:token_transfer_only) { transfer_only.create_new_auth_token }

  before do
    Connecta::Scope::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::Scope::ScopedInbox.create!(inbox_id: other_inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current)
    [agent_a, agent_b, admin_nominal, transfer_only].each do |user|
      create(:inbox_member, inbox: inbox, user: user)
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    Connecta::UserGrant.create!(user_id: agent_a.id, org_unit_id: org_a.id, permission: 'atender')
    Connecta::UserGrant.create!(user_id: agent_b.id, org_unit_id: org_b.id, permission: 'atender')
    Connecta::UserGrant.create!(user_id: admin_nominal.id, org_unit_id: root_unit.id, permission: 'admin_nominal')
    Connecta::UserGrant.create!(user_id: transfer_only.id, org_unit_id: org_a.id, permission: 'transferir')
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conv_a.id, inbox_id: inbox.id, contact_id: contact_a.id,
      org_unit: org_a, state: 'active', case_protocol: protocol, case_version: 1
    )
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conv_b.id, inbox_id: inbox.id, contact_id: contact_b.id,
      org_unit: org_b, state: 'active', case_protocol: protocol, case_version: 1
    )
    Connecta::Scope::ConversationScope.create!(
      conversation_id: origin_conversation.id, inbox_id: inbox.id, contact_id: contact_origin.id,
      org_unit: org_a, state: 'transferred_out', case_protocol: protocol, case_version: 1
    )
    Connecta::Scope::ConversationScope.create!(
      conversation_id: other_conversation.id, inbox_id: other_inbox.id, contact_id: other_contact.id,
      org_unit: other_org, state: 'active', case_protocol: protocol, case_version: 1
    )
  end

  describe 'GET /connecta/protocols/:protocol' do
    it 'admin nativo vê todas as etapas, inclusive a origem transferida' do
      get protocol_path, headers: token_native

      expect(response).to have_http_status(:ok)
      stages = body_json.fetch('stages')
      expect(stages.pluck('conversation_id')).to contain_exactly(
        conv_a.display_id, conv_b.display_id, origin_conversation.display_id
      )
      expect(stages.map { |stage| stage['org_unit_name'] }).to contain_exactly('Setor A', 'Setor B', 'Setor A')
      expect(body_json.to_s).not_to include('phone_number', 'email', 'contact')
    end

    it 'agente A vê só a própria etapa; B não aparece por id nem por nome' do
      get protocol_path, headers: token_a

      expect(response).to have_http_status(:ok)
      stages = body_json.fetch('stages')
      expect(stages.pluck('conversation_id')).to contain_exactly(conv_a.display_id)
      expect(stages.first['org_unit_name']).to eq('Setor A')
      expect(stages.map { |stage| stage['org_unit_name'] }).not_to include('Setor B')
    end

    it 'agente B vê só a própria etapa' do
      get protocol_path, headers: token_b

      expect(response).to have_http_status(:ok)
      expect(body_json.fetch('stages').pluck('conversation_id')).to contain_exactly(conv_b.display_id)
    end

    it 'admin nominal não enumera a etapa transferred_out e audita deny explícito' do
      get protocol_path, headers: token_admin_nominal

      expect(response).to have_http_status(:ok)
      expect(body_json.fetch('stages').pluck('conversation_id')).to contain_exactly(
        conv_a.display_id, conv_b.display_id
      )
      expect(
        Connecta::Scope::AccessAudit.exists?(
          user_id: admin_nominal.id, conversation_id: origin_conversation.id,
          access_path: 'protocol_view', decision: 'deny'
        )
      ).to be(true)
    end

    it 'pagina por cursor sem esconder etapa visível após 200 etapas ocultas' do
      hidden_contact = create(:contact, account: account)
      200.times do
        conversation = create(:conversation, account: account, inbox: inbox, contact: hidden_contact)
        Connecta::Scope::ConversationScope.create!(
          conversation_id: conversation.id, inbox_id: inbox.id, contact_id: hidden_contact.id,
          org_unit: org_a, state: 'transferred_out', case_protocol: protocol, case_version: 1
        )
      end
      visible_contact = create(:contact, account: account)
      visible = create(:conversation, account: account, inbox: inbox, contact: visible_contact, assignee: agent_a)
      Connecta::Scope::ConversationScope.create!(
        conversation_id: visible.id, inbox_id: inbox.id, contact_id: visible_contact.id,
        org_unit: org_a, state: 'active', case_protocol: protocol, case_version: 1
      )
      queries = 0
      subscriber = lambda do |_name, _start, _finish, _id, payload|
        queries += 1 if payload[:sql].to_s.match?(/connecta_conversation_scopes|conversations/i)
      end

      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        get protocol_path, params: { limit: 1 }, headers: token_a
      end

      expect(response).to have_http_status(:ok)
      expect(body_json.fetch('stages').pluck('conversation_id')).to eq([visible.display_id])
      expect(body_json['next_cursor']).to be_nil
      expect(queries).to be <= 20
    end

    it 'agente só com transferir não lê (404 genérico)' do
      get protocol_path, headers: token_transfer_only

      expect(response).to have_http_status(:not_found)
    end

    it 'protocolo de outra conta não vaza para a conta da consulta' do
      get protocol_path, headers: token_native

      expect(response).to have_http_status(:ok)
      expect(body_json.fetch('stages').pluck('conversation_id')).to contain_exactly(
        conv_a.display_id, conv_b.display_id, origin_conversation.display_id
      )
      expect(body_json.fetch('stages').pluck('conversation_id')).not_to include(other_conversation.display_id)
    end

    it 'next_cursor devolve a página seguinte sem repetir etapa' do
      get protocol_path, params: { limit: 1 }, headers: token_native
      expect(response).to have_http_status(:ok)
      first_ids = body_json.fetch('stages').pluck('conversation_id')
      cursor = body_json['next_cursor']
      expect(first_ids.size).to eq(1)
      expect(cursor).to be_present

      get protocol_path, params: { limit: 1, cursor: cursor }, headers: token_native
      expect(response).to have_http_status(:ok)
      second_ids = body_json.fetch('stages').pluck('conversation_id')
      expect(second_ids.size).to eq(1)
      expect(second_ids).not_to eq(first_ids)
    end

    it 'protocolo inexistente ou inválido responde o mesmo 404' do
      get "/api/v1/accounts/#{account.id}/connecta/protocols/NAOEXISTE", headers: token_native
      expect(response).to have_http_status(:not_found)

      get "/api/v1/accounts/#{account.id}/connecta/protocols/#{'A' * 61}", headers: token_native
      expect(response).to have_http_status(:not_found)
    end

    it 'encontra protocolo em minúsculas/mixed case e devolve o valor armazenado' do
      Connecta::Scope::ConversationScope.where(case_protocol: protocol)
                                        .find_each { |scope| scope.update!(case_protocol: protocol.downcase) }

      get "/api/v1/accounts/#{account.id}/connecta/protocols/#{protocol.downcase}", headers: token_native

      expect(response).to have_http_status(:ok)
      expect(body_json.fetch('protocol')).to eq(protocol.downcase)
      expect(body_json.fetch('stages').size).to eq(3)
    end

    it 'protocolo existente só em outra conta responde 404 na conta consultada' do
      other_protocol = "OUTRA#{SecureRandom.hex(3).upcase}"
      Connecta::Scope::ConversationScope.find_by!(conversation_id: other_conversation.id)
                                        .update!(case_protocol: other_protocol)

      get "/api/v1/accounts/#{account.id}/connecta/protocols/#{other_protocol}", headers: token_native

      expect(response).to have_http_status(:not_found)
    end

    it 'não repete consultas de grant/org unit por etapa para o mesmo ator' do
      extra_contact = create(:contact, account: account)
      extra = create(:conversation, account: account, inbox: inbox, contact: extra_contact, assignee: agent_a)
      Connecta::Scope::ConversationScope.create!(
        conversation_id: extra.id, inbox_id: inbox.id, contact_id: extra_contact.id,
        org_unit: org_a, state: 'active', case_protocol: protocol, case_version: 1
      )
      grant_queries = 0
      org_queries = 0
      callback = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql].to_s
        grant_queries += 1 if sql.match?(/connecta_user_grants/i)
        org_queries += 1 if sql.match?(/connecta_org_units/i)
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        get protocol_path, headers: token_a
      end

      expect(response).to have_http_status(:ok)
      expect(body_json.fetch('stages').size).to eq(2)
      expect(grant_queries).to be <= 3
      expect(org_queries).to be <= 3
    end
  end

  describe 'GET /connecta/conversations/metadata' do
    it 'admin nativo recebe raiz/setor/protocolo das conversas visíveis' do
      get(
        metadata_path,
        params: { ids: [conv_a.display_id, conv_b.display_id, origin_conversation.display_id, conv_control.display_id] },
        headers: token_native
      )

      expect(response).to have_http_status(:ok)
      conversations = body_json.fetch('conversations')
      expect(conversations.keys).to contain_exactly(
        conv_a.display_id.to_s, conv_b.display_id.to_s, origin_conversation.display_id.to_s
      )
      expect(conversations[conv_a.display_id.to_s]).to include(
        'case_protocol' => protocol, 'org_unit_name' => 'Setor A', 'root_unit_name' => 'Raiz'
      )
      expect(conversations).not_to have_key(conv_control.display_id.to_s)
    end

    it 'agente A recebe só a própria conversa; agente B não é exposta' do
      get(
        metadata_path,
        params: { ids: "#{conv_a.display_id},#{conv_b.display_id},#{conv_control.display_id}" },
        headers: token_a
      )

      expect(response).to have_http_status(:ok)
      conversations = body_json.fetch('conversations')
      expect(conversations.keys).to contain_exactly(conv_a.display_id.to_s)
      expect(conversations.values.map { |item| item['org_unit_name'] }).not_to include('Setor B')
    end

    it 'admin nominal e transferir-só não recebem metadados da inbox marcada' do
      get metadata_path, params: { ids: conv_a.display_id }, headers: token_admin_nominal
      expect(body_json.fetch('conversations')).to eq({})

      get metadata_path, params: { ids: conv_a.display_id }, headers: token_transfer_only
      expect(body_json.fetch('conversations')).to eq({})
    end

    it 'id de outra conta é omitido' do
      get metadata_path, params: { ids: other_conversation.display_id }, headers: token_native

      expect(response).to have_http_status(:ok)
      expect(body_json.fetch('conversations')).to eq({})
    end

    it 'ids inválidos ou acima do limite são 422' do
      get metadata_path, params: { ids: 'abc' }, headers: token_a
      expect(response).to have_http_status(:unprocessable_entity)

      too_many = Array.new(Connecta::Scope::ConversationMetadata::MAX_IDS + 1) { |index| index + 1 }.join(',')
      get metadata_path, params: { ids: too_many }, headers: token_a
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'busca por protocolo' do
    it 'busca global encontra a etapa autorizada e não a de outro setor' do
      get search_path, params: { q: protocol.downcase }, headers: token_a
      expect(body_json.dig('payload', 'conversations').pluck('id')).to contain_exactly(conv_a.display_id)

      get search_path, params: { q: protocol }, headers: token_b
      expect(body_json.dig('payload', 'conversations').pluck('id')).to contain_exactly(conv_b.display_id)

      get search_path, params: { q: protocol }, headers: token_native
      expect(body_json.dig('payload', 'conversations').pluck('id')).to contain_exactly(
        conv_a.display_id, conv_b.display_id, origin_conversation.display_id
      )

      get search_path, params: { q: protocol }, headers: token_admin_nominal
      expect(body_json.dig('payload', 'conversations')).to be_empty
    end

    it 'busca da lista aplica o mesmo escopo' do
      get conversations_path, params: { q: protocol }, headers: token_a
      expect(body_json.dig('data', 'payload').pluck('id')).to contain_exactly(conv_a.display_id)

      get conversations_path, params: { q: protocol }, headers: token_b
      expect(body_json.dig('data', 'payload').pluck('id')).to contain_exactly(conv_b.display_id)

      get conversations_path, params: { q: protocol }, headers: token_native
      expect(body_json.dig('data', 'payload').pluck('id')).to contain_exactly(
        conv_a.display_id, conv_b.display_id, origin_conversation.display_id
      )

      get conversations_path, params: { q: protocol }, headers: token_transfer_only
      expect(body_json.dig('data', 'payload')).to be_empty
    end

    it 'wildcard digitado é literal e não enumera protocolos' do
      get search_path, params: { q: "#{protocol}%" }, headers: token_native
      expect(body_json.dig('payload', 'conversations').pluck('id')).not_to include(conv_a.display_id, conv_b.display_id)

      get conversations_path, params: { q: "#{protocol}%" }, headers: token_native
      expect(body_json.dig('data', 'payload').pluck('id')).not_to include(conv_a.display_id, conv_b.display_id)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
