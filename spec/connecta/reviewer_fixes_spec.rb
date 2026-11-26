require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta review regressions', type: :request do # rubocop:disable RSpec/DescribeClass
  include_context 'with connecta g0 scope fixture'

  it 'não atribui em lote a pessoa sem atender no setor' do
    BulkActionsJob.perform_now(
      account: account, user: agent_a,
      params: { type: 'Conversation', ids: [conv_a.display_id], fields: { 'assignee_id' => agent_b.id } }
    )
    expect(conv_a.reload.assignee_id).to be_nil
  end

  it 'permite ao gestor liberar com proteção ativa e nega gestor de outro setor' do
    whatsapp_inbox.update!(prevent_assignment_takeover: true)
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit: org_a, permission: 'gerir')
    Connecta::Scope::UserGrant.create!(user_id: agent_b.id, org_unit: org_b, permission: 'gerir')
    conv_a.update!(assignee: agent_a)
    post "#{conversations_path}/#{conv_a.display_id}/assignments",
         params: { assignee_id: nil }, headers: agent_b.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
    expect(conv_a.reload.assignee_id).to eq(agent_a.id)
    post "#{conversations_path}/#{conv_a.display_id}/assignments",
         params: { assignee_id: nil }, headers: manager_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(conv_a.reload.assignee_id).to be_nil
  end

  it 'exclui atribuída a outro agente das métricas para quem tem report_manage' do
    role = create(:custom_role, account: account, permissions: ['report_manage'])
    account_user = AccountUser.find_by!(account: account, user: agent_a)
    account_user.update!(custom_role: role)
    Connecta::Scope::UserGrant.create!(user_id: agent_b.id, org_unit: org_a, permission: 'atender')
    conv_a.update!(assignee: agent_b)
    allow(ReportPolicy).to receive(:new).and_wrap_original do |original, *args|
      policy = original.call(*args)
      allow(policy).to receive(:view?).and_return(account_user.custom_role.permissions.include?('report_manage'))
      policy
    end
    get "/api/v2/accounts/#{account.id}/live_reports/conversation_metrics", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['open']).to eq(2)
  end

  it 'revoga o cache do gestor que tem somente gerir na unidade de origem' do
    Connecta::Scope::UserGrant.where(user_id: manager_a.id).delete_all
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit: org_a, permission: 'gerir')
    allow(ActionCable.server).to receive(:broadcast)
    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)
    Connecta::Runtime::CacheRevocation.scope!(scope)
    expect(ActionCable.server).to have_received(:broadcast).with(
      manager_a.pubsub_token, hash_including(event: 'scope.revoked', data: hash_including(conversation_id: conv_a.display_id))
    )
  end

  it 'revalida status sob lock quando outro agente reivindica após autorização' do
    allow(Connecta::Scope::Gate).to receive(:new).and_wrap_original do |original, user|
      gate = original.call(user)
      if user.id == agent_a.id
        allow(gate).to receive(:write?).and_wrap_original do |write, conversation, **options|
          result = write.call(conversation, **options)
          conv_a.update!(assignee: agent_b) if options[:access_path] == 'conversation_toggle_status'
          result
        end
      end
      gate
    end
    post "#{conversations_path}/#{conv_a.display_id}/toggle_status",
         params: { status: 'resolved' }, headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(conv_a.reload.status).to eq('open')
  end
end
