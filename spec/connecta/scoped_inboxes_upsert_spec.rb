require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# Caminho oficial de enforce por inbox marcada (upsert via PATCH scoped_inboxes).
# Só admin nominal (projeção), com auditoria allow; fora da projeção, 403.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta scoped_inboxes upsert', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:json) { JSON.parse(response.body) }
  let(:scoped_path_for) { ->(inbox_id) { "/api/v1/accounts/#{account.id}/connecta/scoped_inboxes/#{inbox_id}" } }

  before do
    account.account_users.find_by!(user: admin_nominal).update!(role: :administrator)
  end

  it 'cria a marca quando ela não existe (upsert oficial do enforce)' do
    expect do
      patch scoped_path_for.call(control_inbox.id), params: { enforcement: 'enforce' },
                                                    headers: admin_nominal.create_new_auth_token
    end.to change(Connecta::Scope::ScopedInbox, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(json['enforcement']).to eq('enforce')
    expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, access_path: 'enforcement_update',
                                              decision: 'allow')).to exist
  end

  it 'atualiza a marca existente sem duplicar' do
    expect do
      patch scoped_path_for.call(whatsapp_inbox.id), params: { enforcement: 'admin_only' },
                                                      headers: admin_nominal.create_new_auth_token
    end.not_to change(Connecta::Scope::ScopedInbox, :count)

    expect(response).to have_http_status(:success)
    expect(Connecta::Scope::ScopedInbox.find_by(inbox_id: whatsapp_inbox.id).enforcement).to eq('admin_only')
  end

  it 'inbox de outra conta responde 404 (sem vazar existência)' do
    other_account = create(:account)
    foreign_inbox = create(:inbox, account: other_account)

    expect do
      patch scoped_path_for.call(foreign_inbox.id), params: { enforcement: 'enforce' },
                                                     headers: admin_nominal.create_new_auth_token
    end.not_to change(Connecta::Scope::ScopedInbox, :count)

    expect(response).to have_http_status(:not_found)
  end

  it 'não-nominal recebe 403 sem tocar nas marcas' do
    expect do
      patch scoped_path_for.call(control_inbox.id), params: { enforcement: 'enforce' },
                                                     headers: agent_a.create_new_auth_token
    end.not_to change(Connecta::Scope::ScopedInbox, :count)

    expect(response).to have_http_status(:forbidden)
  end
end
