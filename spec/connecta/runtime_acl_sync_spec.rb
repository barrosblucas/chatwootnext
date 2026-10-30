require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'

# Contrato de fio v1 §8 (WP→fork): ACL sync com account_id validado no controller
# (403 se divergente). Também é heartbeat: events vazio renova o heartbeat da ACL;
# versão velha é ignorada sem renovar o heartbeat.
Connecta::G0ScopeSchema.ensure!
# Scope aponta às tabelas de produto (mesmo mapa de G0Adapter::TABLES; ver support/g0_product_tables.rb).
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · ACL sync (item 8)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:secret) { 'test-platform-to-fork-secret' }
  let(:sync_path) { '/connecta/v1/acl/sync' }

  def signed_headers(timestamp, request_path, request_body)
    canonical = [timestamp, 'POST', request_path, request_body].join('.')
    {
      'X-Connecta-Timestamp' => timestamp,
      'X-Connecta-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)}",
      'Content-Type' => 'application/json'
    }
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => account.id.to_s,
                        'CONNECTA_PLATFORM_TO_FORK_SECRET' => secret
                      ))
    # Contrato singleton da ACL (índice idx_connecta_acl_sync_singleton, WHERE id = 1): o serviço
    # lê a linha id = 1. A semente do fixture usa id de sequência e deixaria o serviço criar outra linha.
    Connecta::Scope::AclSyncState.delete_all
    Connecta::Scope::AclSyncState.create!(id: 1, last_version: 1, last_heartbeat_at: Time.current)
  end

  it 'sync vazio renova o heartbeat da ACL' do
    Connecta::Scope::AclSyncState.find(1).update!(last_heartbeat_at: 10.minutes.ago)

    body = { account_id: account.id, projection_version: 1, events: [] }.to_json
    post sync_path, params: body, headers: signed_headers(Time.current.to_i.to_s, sync_path, body)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['status']).to eq('applied')
    expect(Connecta::Scope::AclSyncState.order(:id).first.last_heartbeat_at).to be > 1.minute.ago
  end

  it 'versao velha e ignorada sem renovar o heartbeat' do
    Connecta::Scope::AclSyncState.find(1).update!(last_version: 5, last_heartbeat_at: 50.seconds.ago)
    heartbeat_before = Connecta::Scope::AclSyncState.order(:id).first.last_heartbeat_at

    body = { account_id: account.id, projection_version: 3, events: [] }.to_json
    post sync_path, params: body, headers: signed_headers(Time.current.to_i.to_s, sync_path, body)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['status']).to eq('stale')
    expect(Connecta::Scope::AclSyncState.order(:id).first.last_heartbeat_at.to_i).to eq(heartbeat_before.to_i)
  end

  it 'account divergente responde 403' do
    body = { account_id: account.id + 1, projection_version: 1, events: [] }.to_json
    post sync_path, params: body, headers: signed_headers(Time.current.to_i.to_s, sync_path, body)

    expect(response).to have_http_status(:forbidden)
  end

  it 'account ausente responde 403' do
    body = { projection_version: 1, events: [] }.to_json
    post sync_path, params: body, headers: signed_headers(Time.current.to_i.to_s, sync_path, body)

    expect(response).to have_http_status(:forbidden)
  end

  it 'campos desconhecidos sao ignorados' do
    body = { account_id: account.id, projection_version: 1, events: [], future_field: 'x' }.to_json
    post sync_path, params: body, headers: signed_headers(Time.current.to_i.to_s, sync_path, body)

    expect(response).to have_http_status(:ok)
  end
end
