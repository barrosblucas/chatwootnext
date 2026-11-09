require_relative '../../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative '../../connecta/support/g0_scope_schema'
require_relative '../../connecta/support/g0_scope_fixture'

# Correção 01 (2026-11-09): GET /connecta/outbound_dispatches exigia admin_nominal via
# Pundit, e o handler global convertia a negação em 401 — o frontend só suprime 403,
# então o agente vinculado via identity_link recebia o popup "You are not authorized".
# O filtro agora responde 403 local (mesmo padrão de acl/scoped_inboxes), sem tocar o
# handler global: 401 segue reservado a sessão ausente/inválida.
# Specs de serviço: rodam só via scripts/connecta/g0_test_env.sh --spec (CI).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · autorização de outbound_dispatches (correção 01)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let!(:outgoing_message) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a,
                     message_type: :outgoing, content: 'resposta incerta')
  end
  # F5 shard7 (2026-11-09): neste shard o MessageHook (transfer_activation) e o
  # retarget do G0Adapter (runtime_acl_sync) carregam no mesmo processo; o hook
  # já insere a linha queued de outgoing_message na mesma tabela
  # (connecta_outbound_dispatches, unique em message_id) antes deste fixture, e
  # o create! explícito estourava PG::UniqueViolation nos 5 exemplos. Reuso
  # idempotente: sem hook cria a linha uncertain; com hook reaproveita a linha
  # queued e a promove a uncertain. Nenhuma asserção de autorização foi tocada.
  let!(:uncertain_dispatch) do
    record = Connecta::OutboundDispatch.find_or_initialize_by(message_id: outgoing_message.id)
    record.conversation = conv_a
    record.state = 'uncertain'
    record.attempted_at ||= Time.current
    record.save!
    record
  end

  let(:index_path) { "/api/v1/accounts/#{account.id}/connecta/outbound_dispatches" }
  let(:resolve_path) { "#{index_path}/#{uncertain_dispatch.id}/resolve" }

  it 'agente vinculado sem admin_nominal recebe 403 sem vazar despachos (sem popup 401)' do
    get index_path, headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
    expect(json['error']).to eq('Admin nominal permission required')
    expect(json).not_to have_key('dispatches')
  end

  it 'PATCH do agente é negado com 403 sem mutar estado nem auditar' do
    expect do
      patch resolve_path, params: { state: 'failed' }, headers: agent_a.create_new_auth_token, as: :json
    end.not_to change(Connecta::AccessAudit, :count)

    expect(response).to have_http_status(:forbidden)
    expect(uncertain_dispatch.reload.state).to eq('uncertain')
  end

  it 'admin nominal lista os despachos pendentes' do
    get index_path, headers: admin_nominal.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(json['dispatches'].map { |row| row['id'] }).to include(uncertain_dispatch.id)
  end

  it 'admin nominal resolve uncertain com connector id' do
    patch resolve_path, params: { state: 'accepted', connector_message_id: 'wa-123' },
                        headers: admin_nominal.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(uncertain_dispatch.reload).to have_attributes(state: 'accepted', connector_message_id: 'wa-123')
  end

  it 'sessão ausente segue 401 (sem token)' do
    get index_path

    expect(response).to have_http_status(:unauthorized)
  end
end
