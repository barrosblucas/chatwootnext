require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Contrato de fio v1 §10 (WP→fork): conversas = display_id; account_id validado
# (403 se divergente); 409 em estado ou versão divergente; expected_state
# reception ou pending_activation; ativação idempotente.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
# Scope aponta às tabelas de produto (mesmo mapa de G0Adapter::TABLES; ver support/g0_product_tables.rb).
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · ativacao de escopo (item 10)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:secret) { 'test-platform-to-fork-secret' }
  let(:activate_path) { "/connecta/v1/scopes/#{conv_a.display_id}/activate" }

  def signed_headers(timestamp, request_path, request_body)
    canonical = [timestamp, 'POST', request_path, request_body].join('.')
    {
      'X-Connecta-Timestamp' => timestamp,
      'X-Connecta-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)}",
      'Content-Type' => 'application/json'
    }
  end

  # Os call sites passam o corpo como keywords (account_id:, expected_state:, ...); display_id é opcional.
  def activate(display_id: conv_a.display_id, **body_hash)
    path = "/connecta/v1/scopes/#{display_id}/activate"
    body = body_hash.to_json
    post path, params: body, headers: signed_headers(Time.current.to_i.to_s, path, body)
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => account.id.to_s,
                        'CONNECTA_PLATFORM_TO_FORK_SECRET' => secret
                      ))
  end

  it 'ativa escopo reception com display_id e account valido' do
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'reception', case_version: 0)

    activate(account_id: account.id, expected_state: 'reception', org_unit_id: org_a.id.to_s,
             case_protocol: 'CASO-A', session_ref: 'sess-1', case_version: 1)

    expect(response).to have_http_status(:ok)
    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)
    expect(scope).to have_attributes(state: 'active', case_version: 1, case_protocol: 'CASO-A')
  end

  it 'rejeita divergencia de estado com 409 sem efeito' do
    activate(account_id: account.id, expected_state: 'pending_activation', org_unit_id: org_b.id.to_s,
             case_protocol: 'CASO-A', session_ref: 'sess-9', case_version: 2)

    expect(response).to have_http_status(:conflict)
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).state).to eq('active')
  end

  it 'rejeita versao que nao avanca com 409' do
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'reception', case_version: 5)

    activate(account_id: account.id, expected_state: 'reception', org_unit_id: org_a.id.to_s,
             case_protocol: 'CASO-A', session_ref: 'sess-1', case_version: 5)

    expect(response).to have_http_status(:conflict)
  end

  it 'reativacao identica e idempotente (already_activated)' do
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)
                                      .update!(state: 'active', case_protocol: 'CASO-A',
                                               platform_session_ref: 'sess-1', case_version: 2)

    activate(account_id: account.id, expected_state: 'reception', org_unit_id: org_a.id.to_s,
             case_protocol: 'CASO-A', session_ref: 'sess-1', case_version: 2)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['status']).to eq('already_activated')
  end

  it 'account divergente responde 403' do
    activate(account_id: account.id + 1, expected_state: 'reception', org_unit_id: org_a.id.to_s,
             case_protocol: 'CASO-A', session_ref: 'sess-1', case_version: 1)

    expect(response).to have_http_status(:forbidden)
  end

  it 'expected_state invalido responde 409' do
    activate(account_id: account.id, expected_state: 'closed', org_unit_id: org_a.id.to_s,
             case_protocol: 'CASO-A', session_ref: 'sess-1', case_version: 1)

    expect(response).to have_http_status(:conflict)
  end
end
