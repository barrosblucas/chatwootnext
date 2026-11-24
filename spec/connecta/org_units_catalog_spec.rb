require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'

# Catalogo de setores do dashboard Connecta (filtro Setor): GET somente leitura
# que expoe id/nome das unidades habilitadas legiveis sob a mesma regra
# account-scoped da selecao `connecta_org_unit_id` (DashboardTabs: admin nativo
# da conta ou projecao utilizavel + grant de leitura com prefixo). Projecao
# ausente/inutilizavel falha fechado para lista vazia, sem erro que permita
# sondar grants. Nenhuma decisao de autorizacao e mockada; so a borda HTTP
# fork->WP e dublada (sem rede).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · catalogo de setores do dashboard (org units)', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:marked_inbox) { create(:inbox, account: account) }
  let(:control_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_a) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:stale_user) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  let!(:org_a) { Connecta::Scope::OrgUnit.create!(name: 'Setor A', path: '/setor-a/') }
  let!(:org_a1) { Connecta::Scope::OrgUnit.create!(name: 'Setor A Norte', parent: org_a, path: '/setor-a/norte/') }
  let!(:org_b) { Connecta::Scope::OrgUnit.create!(name: 'Setor B', path: '/setor-b/') }
  let!(:org_c) { Connecta::Scope::OrgUnit.create!(name: 'Setor C', path: '/setor-c/') }

  let!(:convs) do
    disabled = Connecta::Scope::OrgUnit.create!(name: 'Desativado', path: '/desativado/', enabled: false)
    built = {
      a_open: open_conversation!(marked_inbox),
      a1_open: open_conversation!(marked_inbox),
      b_open: open_conversation!(marked_inbox),
      c_open: open_conversation!(marked_inbox),
      generic: open_conversation!(control_inbox)
    }
    put_scope!(built[:a_open], unit: org_a, protocol: 'CAT00000001')
    put_scope!(built[:a1_open], unit: org_a1, protocol: 'CAT00000002')
    put_scope!(built[:b_open], unit: org_b, protocol: 'CAT00000003')
    put_scope!(built[:c_open], unit: org_c, protocol: 'CAT00000004')
    Connecta::Scope::UserGrant.create!(user_id: agent.id, org_unit: disabled, permission: 'atender')
    built
  end

  def catalog_path
    "/api/v1/accounts/#{account.id}/connecta/org_units"
  end

  def tabs_path
    "/api/v1/accounts/#{account.id}/conversations"
  end

  def meta_path
    "#{tabs_path}/meta"
  end

  def other_admin
    create(:user, account: other_account, role: :administrator)
  end

  def json
    JSON.parse(response.body)
  end

  def catalog
    json['org_units']
  end

  def open_conversation!(target_inbox, assignee: nil)
    contact = create(:contact, account: account)
    create(:conversation, account: account, inbox: target_inbox, contact: contact, status: :open, assignee: assignee)
  end

  def put_scope!(conversation, unit:, protocol:)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
      org_unit: unit, state: 'active', case_protocol: protocol, case_version: 1
    )
  end

  before do
    [agent, agent_a, outsider, admin].each do |user|
      create(:inbox_member, inbox: marked_inbox, user: user)
      create(:inbox_member, inbox: control_inbox, user: user)
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    create(:inbox_member, inbox: marked_inbox, user: stale_user)
    Connecta::Scope::ScopedInbox.create!(inbox_id: marked_inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current)
    Connecta::Scope::UserGrant.create!(user_id: agent.id, org_unit: org_a, permission: 'atender')
    Connecta::Scope::UserGrant.create!(user_id: agent.id, org_unit: org_b, permission: 'acompanhar')
    Connecta::Scope::UserGrant.create!(user_id: agent_a.id, org_unit: org_a, permission: 'atender')
    Connecta::Scope::UserGrant.create!(user_id: stale_user.id, org_unit: org_a, permission: 'atender')
  end

  def opt_in(tab, extra = {})
    { connecta_dashboard: 'true', connecta_tab: tab }.merge(extra)
  end

  describe 'catalogo' do
    it 'expoe so id/nome das habilitadas legiveis, com descendente e sem derivar de inbox', :aggregate_failures do
      get catalog_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(catalog.map { |row| row['name'] }).to eq(['Setor A', 'Setor A Norte', 'Setor B'])
      expect(catalog.map { |row| row.keys.sort }).to all(eq(%w[id name]))
      expect(catalog.map { |row| row['id'] }).to contain_exactly(org_a.id, org_a1.id, org_b.id)
    end

    it 'grant so no ancestral cobre o descendente, sem vazar outros setores', :aggregate_failures do
      get catalog_path, headers: agent_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(catalog.map { |row| row['name'] }).to eq(['Setor A', 'Setor A Norte'])
    end

    it 'sem grant a projecao utilizavel recebe lista vazia', :aggregate_failures do
      get catalog_path, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(catalog).to eq([])
    end

    it 'projecao inutilizavel falha fechado mesmo com grant', :aggregate_failures do
      get catalog_path, headers: stale_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(catalog).to eq([])
    end

    it 'admin nativo ve todas as habilitadas, sem a desativada', :aggregate_failures do
      get catalog_path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(catalog.map { |row| row['name'] }).to eq(['Setor A', 'Setor A Norte', 'Setor B', 'Setor C'])
    end

    it 'nao membro da conta nao alcanca o catalogo de outra conta', :aggregate_failures do
      get catalog_path, headers: other_admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json).not_to have_key('org_units')
    end

    it 'membro nao alcanca o catalogo de conta onde nao pertence', :aggregate_failures do
      get "/api/v1/accounts/#{other_account.id}/connecta/org_units",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json).not_to have_key('org_units')
    end
  end

  describe 'selecao compartilha a fronteira do catalogo' do
    it 'setor descendente filtra lista e contagem na mesma inbox Baileys', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: org_a1.id),
                     headers: agent_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['data']['payload'].map { |row| row['id'] }).to contain_exactly(
        convs[:a1_open].display_id, convs[:generic].display_id
      )

      get meta_path, params: opt_in('aguardando', connecta_org_unit_id: org_a1.id),
                     headers: agent_a.create_new_auth_token, as: :json
      expect(json['meta']).to include('all_count' => 2)
    end

    it 'limpar a selecao restaura o agregado autorizado', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: org_a.id),
                     headers: agent.create_new_auth_token, as: :json
      narrowed = json['data']['payload'].map { |row| row['id'] }

      get tabs_path, params: opt_in('aguardando'), headers: agent.create_new_auth_token, as: :json
      aggregate = json['data']['payload'].map { |row| row['id'] }

      expect(narrowed).to contain_exactly(
        convs[:a_open].display_id, convs[:a1_open].display_id, convs[:generic].display_id
      )
      expect(aggregate).to contain_exactly(
        convs[:a_open].display_id, convs[:a1_open].display_id,
        convs[:b_open].display_id, convs[:generic].display_id
      )
    end
  end
end
