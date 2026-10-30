require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF4 HTTP (spike G0, rev. 2, bloco A3): notificações existentes somem da lista/contagem e viram 404 na ação
# depois da perda de acesso. Casos ESCRITOS e NÃO EXECUTADOS; A1/A2 implementam o filtro em runtime (plano rev. 2).
# Rotas/factories/fixtures nativas e estáveis; nenhum Gate/Finder/Controller stubado; sem jobs reais nem teardown.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Casos RF4/A3 juntam lista+count+unread+paginação/efeitos (AC1/AC2); expectativas agrupadas por caso.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Connecta G0 · notificações existentes após perda de acesso (RF4/A3)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:notifications_path) { "/api/v1/accounts/#{account.id}/notifications" }

  def create_scoped_notification!(user:, conversation:)
    create(:notification,
           user: user, account: account, primary_actor: conversation,
           notification_type: :conversation_assignment)
  end

  def mark_all_unread!
    Notification.where(account_id: account.id).find_each do |notification|
      notification.update!(read_at: nil, snoozed_until: nil)
    end
  end

  def notification_payload_ids(body)
    JSON.parse(body).dig('data', 'payload').pluck('id')
  end

  def notification_meta(body)
    JSON.parse(body).dig('data', 'meta')
  end

  before do
    clear_enqueued_jobs
    [agent_a, agent_b, manager_a, member_without_grant, admin_nominal].each do |user|
      user.notification_settings.find_by(account_id: account.id).update!(
        selected_email_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"email_#{type}" },
        selected_push_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"push_#{type}" }
      )
    end
  end

  after do
    clear_enqueued_jobs
  end

  it 'revoga grant de A: lista/count/unread mostram só o controle; página 2 fica vazia ' \
     '(filtro antes da paginação)' do
    base_time = Time.zone.now.change(usec: 0)
    control = create_scoped_notification!(user: agent_a, conversation: conv_control)
    hidden = Array.new(16) do |index|
      create_scoped_notification!(user: agent_a, conversation: conv_a).tap do |notification|
        # Últimas primeiro na ordenação nativa (last_activity_at desc): ocultas em page 1, controle em page 2.
        notification.update!(created_at: base_time + (index + 1).seconds,
                             updated_at: base_time + (index + 1).seconds,
                             last_activity_at: base_time + (index + 1).seconds)
      end
    end
    control.update!(created_at: base_time, updated_at: base_time, last_activity_at: base_time)
    mark_all_unread!
    hidden_ids = hidden.map(&:id)

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

    get notifications_path, headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(notification_payload_ids(response.body)).to contain_exactly(control.id)
    expect(notification_meta(response.body)['count']).to eq(1)

    get "#{notifications_path}/unread_count", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq(1)

    get notifications_path, params: { page: 2 }, headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(notification_payload_ids(response.body)).to be_empty

    get notifications_path, params: { page: 2 }, headers: member_without_grant.create_new_auth_token
    expect(notification_payload_ids(response.body)).not_to include(*hidden_ids)

    expect(Notification.where(user: agent_a).count).to eq(17)
    expect(Notification.where(id: hidden_ids).count).to eq(16)
  end

  it 'conversa transferida para B com saída registrada some da lista de A (sem LocalTransaction RF6)' do
    control = create_scoped_notification!(user: agent_a, conversation: conv_control)
    visible_before = create_scoped_notification!(user: agent_a, conversation: conv_a)
    mark_all_unread!

    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)
    scope.update!(org_unit: org_b, state: 'transferred_out')

    get notifications_path, headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(notification_payload_ids(response.body)).to contain_exactly(control.id)
    expect(notification_meta(response.body)['count']).to eq(1)

    get "#{notifications_path}/unread_count", headers: agent_a.create_new_auth_token
    expect(JSON.parse(response.body)).to eq(1)

    expect(Notification.where(user: agent_a).count).to eq(2)
    expect(Notification.find(visible_before.id).read_at).to be_nil
  end

  it 'admin nominal não lista marcada nem grava allow indevido; membro sem grant segue nativo no controle' do
    control_for_admin = create_scoped_notification!(user: admin_nominal, conversation: conv_a)
    control_for_member = create_scoped_notification!(user: member_without_grant, conversation: conv_control)
    mark_all_unread!

    get notifications_path, headers: admin_nominal.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(notification_payload_ids(response.body)).to be_empty
    expect(notification_meta(response.body)['count']).to eq(0)

    get "#{notifications_path}/unread_count", headers: admin_nominal.create_new_auth_token
    expect(JSON.parse(response.body)).to eq(0)
    expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, access_path: 'list').count).to eq(0)

    get notifications_path, headers: member_without_grant.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(notification_payload_ids(response.body)).to contain_exactly(control_for_member.id)
    expect(Notification.find(control_for_admin.id).read_at).to be_nil
    expect(Notification.find(control_for_member.id).read_at).to be_nil
  end

  it 'membro sem grant com conversa de controle lista o controle (regra nativa preservada)' do
    control = create_scoped_notification!(user: member_without_grant, conversation: conv_control)
    mark_all_unread!

    get notifications_path, headers: member_without_grant.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(notification_payload_ids(response.body)).to contain_exactly(control.id)
    expect(notification_meta(response.body)['count']).to eq(1)

    get "#{notifications_path}/unread_count", headers: member_without_grant.create_new_auth_token
    expect(JSON.parse(response.body)).to eq(1)
  end

  it 'PATCH em notificação oculta responde 404 sem marcar leitura; visível responde 200 sem tocar a oculta' do
    hidden = create_scoped_notification!(user: agent_a, conversation: conv_a)
    visible = create_scoped_notification!(user: agent_a, conversation: conv_control)
    mark_all_unread!

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

    patch "#{notifications_path}/#{hidden.id}", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.read_at).to be_nil

    patch "#{notifications_path}/#{visible.id}", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(visible.reload.read_at).not_to be_nil
    expect(hidden.reload.read_at).to be_nil
  end

  it 'snooze em notificação oculta responde 404 sem reagendar; visível responde 200 sem tocar a oculta' do
    hidden = create_scoped_notification!(user: agent_a, conversation: conv_a)
    visible = create_scoped_notification!(user: agent_a, conversation: conv_control)
    mark_all_unread!
    snoozed_until = 2.days.from_now.iso8601

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

    post "#{notifications_path}/#{hidden.id}/snooze", params: { snoozed_until: snoozed_until },
                                                      headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.snoozed_until).to be_nil

    post "#{notifications_path}/#{visible.id}/snooze", params: { snoozed_until: snoozed_until },
                                                       headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(visible.reload.snoozed_until).not_to be_nil
    expect(hidden.reload.snoozed_until).to be_nil
  end

  it 'unread em notificação oculta responde 404 sem remarcar; visível responde 200 sem tocar a oculta' do
    hidden = create_scoped_notification!(user: agent_a, conversation: conv_a)
    visible = create_scoped_notification!(user: agent_a, conversation: conv_control)
    hidden.update!(read_at: Time.current)
    visible.update!(read_at: Time.current)

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

    post "#{notifications_path}/#{hidden.id}/unread", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.read_at).not_to be_nil

    post "#{notifications_path}/#{visible.id}/unread", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(visible.reload.read_at).to be_nil
    expect(hidden.reload.read_at).not_to be_nil
  end

  it 'DELETE em notificação oculta responde 404 sem apagar; visível apaga só a própria linha' do
    hidden = create_scoped_notification!(user: agent_a, conversation: conv_a)
    visible = create_scoped_notification!(user: agent_a, conversation: conv_control)
    mark_all_unread!

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

    delete "#{notifications_path}/#{hidden.id}", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(Notification.where(id: hidden.id).count).to eq(1)

    delete "#{notifications_path}/#{visible.id}", headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(Notification.where(id: visible.id).count).to eq(0)
    expect(Notification.where(id: hidden.id).count).to eq(1)
  end
end
# rubocop:enable RSpec/MultipleExpectations
