require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# Criação de inbox WhatsApp pelo guard do spike G0 (inbox_hook.rb). Regra: admin nominal E administrador nativo da conta.
# Regressão: o guard roda como prepend_before_action, antes de current_account; Current.account_user ainda é nil nesse ponto.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta inbox create (admin nominal e nativo)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:inboxes_path) { "/api/v1/accounts/#{account.id}/inboxes" }
  let(:whatsapp_params) do
    { name: 'Nova WhatsApp', channel: { type: 'whatsapp', phone_number: '+5511999990009', provider: 'baileys',
                                        provider_config: { mark_as_read: true, presence_subscribe: false } } }
  end

  before do
    stub_request(:any, /.*/).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    account.account_users.find_by!(user: admin_nominal).update!(role: :administrator)
  end

  it 'admin nominal que também é administrador nativo cria inbox WhatsApp (guard não nega)' do
    post inboxes_path, params: whatsapp_params, headers: admin_nominal.create_new_auth_token

    expect(response).not_to have_http_status(:forbidden)
    expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, access_path: 'inbox_create', decision: 'allow')).to exist
  end

  it 'administrador nativo sem grant admin_nominal não cria inbox WhatsApp (403, sem registro)' do
    native_only = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: native_only).update!(role: :administrator)

    expect do
      post inboxes_path, params: whatsapp_params, headers: native_only.create_new_auth_token
    end.not_to change(Inbox, :count)

    expect(response).to have_http_status(:forbidden)
    expect(Connecta::Scope::AccessAudit.where(user_id: native_only.id, access_path: 'inbox_create', decision: 'deny')).to exist
  end

  it 'agente comum não cria inbox WhatsApp (403, sem registro)' do
    expect do
      post inboxes_path, params: whatsapp_params, headers: agent_a.create_new_auth_token
    end.not_to change(Inbox, :count)

    expect(response).to have_http_status(:forbidden)
  end

  # Bootstrap C7: conta fresca (nenhuma inbox marcada) ainda não tem projeção/admin_nominal
  # sincronizado — o administrador nativo pode criar a primeira inbox WhatsApp, auditado
  # como allow em 'inbox_create_bootstrap'. Assim que há marca, vale a regra nominal.
  context 'bootstrap (conta sem nenhuma inbox marcada)' do
    before { Connecta::Scope::ScopedInbox.delete_all }

    it 'administrador nativo cria a primeira inbox WhatsApp (allow bootstrap auditado)' do
      native_admin = create(:user, account: account, role: :agent)
      account.account_users.find_by!(user: native_admin).update!(role: :administrator)

      post inboxes_path, params: whatsapp_params, headers: native_admin.create_new_auth_token

      expect(response).not_to have_http_status(:forbidden)
      expect(Connecta::Scope::AccessAudit.where(user_id: native_admin.id, access_path: 'inbox_create_bootstrap',
                                                decision: 'allow')).to exist
      expect(Connecta::Scope::AccessAudit.where(user_id: native_admin.id, decision: 'deny')).not_to exist
    end

    it 'não-admin continua negado mesmo sem marca (sem bootstrap para quem não administra)' do
      expect do
        post inboxes_path, params: whatsapp_params, headers: agent_a.create_new_auth_token
      end.not_to change(Inbox, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'conta já marcada (regra nominal mantida)' do
    it 'administrador nativo sem grant admin_nominal continua 403 com deny' do
      native_only = create(:user, account: account, role: :agent)
      account.account_users.find_by!(user: native_only).update!(role: :administrator)

      expect do
        post inboxes_path, params: whatsapp_params, headers: native_only.create_new_auth_token
      end.not_to change(Inbox, :count)

      expect(response).to have_http_status(:forbidden)
      expect(Connecta::Scope::AccessAudit.where(user_id: native_only.id, access_path: 'inbox_create',
                                                decision: 'deny')).to exist
    end
  end
end
