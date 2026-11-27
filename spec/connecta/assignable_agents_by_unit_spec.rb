require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# Departamento nos assignees: o endpoint lista só usuários do próprio setor
# (grupos por setor para gestor/admin), em ordem alfabética pt-BR, sem o
# usuário de recepção. Sem mocks de autorização: Gate, Policy e projeção reais.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · assignees por departamento (endpoint)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:endpoint_path) { "/api/v1/accounts/#{account.id}/connecta/assignable_agents" }

  let!(:alvaro) { create(:user, account: account, role: :agent, name: 'Álvaro Nunes') }
  let!(:beatriz) { create(:user, account: account, role: :agent, name: 'beatriz luz') }
  let!(:carlos) { create(:user, account: account, role: :agent, name: 'Carlos Mendes') }
  let!(:diana) { create(:user, account: account, role: :agent, name: 'Diana Dupla') }
  let!(:reception_user) { create(:user, account: account, role: :agent, name: 'Zé Recepção') }
  let!(:gestor_um) { create(:user, account: account, role: :agent, name: 'Gestor Um') }
  let!(:native_admin) { create(:user, account: account, role: :administrator, name: 'Admin Nativo') }

  before do
    [alvaro, beatriz, diana, reception_user].each do |user|
      Connecta::Scope::UserGrant.create!(user_id: user.id, org_unit: org_a, permission: 'atender')
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    [carlos, diana].each do |user|
      Connecta::Scope::UserGrant.create!(user_id: user.id, org_unit: org_b, permission: 'atender')
    end
    [carlos, gestor_um].each do |user|
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1) unless Connecta::Scope::UserAuthEpoch.exists?(user_id: user.id)
    end
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit: org_a, permission: 'gerir')
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit: org_b, permission: 'gerir')
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit: org_a, permission: 'transferir')
    Connecta::Scope::UserGrant.create!(user_id: gestor_um.id, org_unit: org_a, permission: 'gerir')
    stub_const('ENV', ENV.to_h.merge('CONNECTA_RECEPTION_SENDER_USER_IDS' => reception_user.id.to_s))
    agent_a.update!(name: 'Agente A')
  end

  def get_agents(actor, conversation_ids)
    get endpoint_path, params: { conversation_ids: Array(conversation_ids).map(&:display_id) },
                       headers: actor.create_new_auth_token
    JSON.parse(response.body)
  end

  describe 'conversa única em inbox marcada' do
    it 'atendente vê só o grupo do próprio setor, em ordem alfabética, sem recepção nem admins sem grant (AC1, AC4)' do
      body = get_agents(agent_a, conv_a)

      expect(response).to have_http_status(:ok)
      expect(body['grouped']).to be(false)
      expect(body['conversation_org_unit_id']).to eq(org_a.id)
      expect(body['groups'].size).to eq(1)
      group = body['groups'].first
      expect(group['org_unit_id']).to eq(org_a.id)
      expect(group['org_unit_name']).to eq('Setor A')
      names = group['agents'].map { |agent| agent['name'] }
      expect(names).to eq(['Agente A', 'Álvaro Nunes', 'beatriz luz', 'Diana Dupla'])
    end

    it 'expõe o shape do agente da lista nativa (AC1)' do
      body = get_agents(agent_a, conv_a)

      expect(response).to have_http_status(:ok)
      expect(body['groups'].first['agents'].first.keys).to include('id', 'name', 'email', 'role', 'availability_status')
    end

    it 'lista do setor exclui recepção e admins sem grant (AC4)' do
      body = get_agents(agent_a, conv_a)
      group = body['groups'].first

      ids = group['agents'].map { |agent| agent['id'] }
      expect(ids).not_to include(reception_user.id, native_admin.id, agent_b.id, carlos.id)
    end

    it 'gestor com gerir em 2 setores vê exatamente esses 2 grupos (AC3)' do
      body = get_agents(manager_a, conv_a)

      expect(response).to have_http_status(:ok)
      expect(body['grouped']).to be(true)
      expect(body['groups'].map { |group| group['org_unit_name'] }).to eq(['Setor A', 'Setor B'])
      group_b = body['groups'].find { |group| group['org_unit_name'] == 'Setor B' }
      names_b = group_b['agents'].map { |agent| agent['name'] }
      expect(names_b).to contain_exactly(agent_b.name, 'Carlos Mendes', 'Diana Dupla')
      expect(names_b).to eq(names_b.sort_by { |n| I18n.transliterate(n.to_s).downcase })
    end

    it 'gestor com gerir em 1 setor vê 1 grupo (AC3)' do
      body = get_agents(gestor_um, conv_a)

      expect(response).to have_http_status(:ok)
      expect(body['grouped']).to be(false)
      expect(body['groups'].map { |group| group['org_unit_name'] }).to eq(['Setor A'])
    end

    it 'admin nativo vê um grupo por setor com elegíveis, tudo em ordem alfabética (AC2)' do
      body = get_agents(native_admin, conv_a)

      expect(response).to have_http_status(:ok)
      expect(body['grouped']).to be(true)
      expect(body['groups'].map { |group| group['org_unit_name'] }).to eq(['Setor A', 'Setor B', 'Sub A1'])
      body['groups'].each do |group|
        names = group['agents'].map { |agent| agent['name'] }
        expect(names).to eq(names.sort_by { |n| I18n.transliterate(n.to_s).downcase })
        expect(names).not_to include('Zé Recepção', 'Admin Nativo')
      end
      group_a1 = body['groups'].find { |group| group['org_unit_name'] == 'Sub A1' }
      expect(group_a1['agents'].map { |agent| agent['name'] }).to include('Agente A', 'Diana Dupla')
    end

    it 'sem grant de leitura a conversa não é revelada (404)' do
      get endpoint_path, params: { conversation_ids: [conv_a.display_id] },
                         headers: member_without_grant.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'sem conversation_ids responde 422' do
      get endpoint_path, headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'bulk e inbox sem escopo' do
    it 'bulk de dois setores retorna só a interseção, sem cross-unit (AC7)' do
      body = get_agents(manager_a, [conv_a, conv_b])

      expect(response).to have_http_status(:ok)
      expect(body['grouped']).to be(false)
      expect(body['conversation_org_unit_id']).to be_nil
      expect(body['groups'].size).to eq(1)
      group = body['groups'].first
      expect(group['org_unit_id']).to be_nil
      expect(group['agents'].map { |agent| agent['name'] }).to eq(['Diana Dupla'])
    end

    it 'conversa de inbox sem marca usa a lista nativa da inbox (AC unscoped)' do
      member = create(:user, account: account, role: :agent, name: 'Membro Controle')
      create(:inbox_member, inbox: control_inbox, user: member)
      Connecta::Scope::UserAuthEpoch.create!(user_id: member.id, epoch: 1)

      body = get_agents(member, conv_control)

      expect(response).to have_http_status(:ok)
      expect(body['grouped']).to be(false)
      expect(body['conversation_org_unit_id']).to be_nil
      group = body['groups'].first
      expect(group['org_unit_id']).to be_nil
      expect(group['org_unit_name']).to be_nil
      expect(group['agents'].map { |agent| agent['name'] }).to eq(
        (['Agente A', 'Admin Nativo', 'Membro Controle']).sort_by { |n| I18n.transliterate(n.to_s).downcase }
      )
    end
  end
end
