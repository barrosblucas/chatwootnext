require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'

# Contrato de fio v1 §9 (WP→fork) + defeito 3b: ack {epoch} só após barreira local
# efetiva. Epoch igual com registro ainda ativo revoga de verdade (broadcast +
# desconexão); epoch maior revoga; revogação já aplicada é idempotente (ack sem
# reescrever, sem rebroadcast). Account divergente → 403.
Connecta::G0ScopeSchema.ensure!
# Scope aponta às tabelas de produto (mesmo mapa de G0Adapter::TABLES; ver support/g0_product_tables.rb).
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · ACL revoke (item 9)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:secret) { 'test-platform-to-fork-secret' }
  let(:revoke_path) { '/connecta/v1/acl/revoke' }

  def signed_headers(timestamp, request_path, request_body)
    canonical = [timestamp, 'POST', request_path, request_body].join('.')
    {
      'X-Connecta-Timestamp' => timestamp,
      'X-Connecta-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)}",
      'Content-Type' => 'application/json'
    }
  end

  def revoke(body_hash)
    body = body_hash.to_json
    post revoke_path, params: body, headers: signed_headers(Time.current.to_i.to_s, revoke_path, body)
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => account.id.to_s,
                        'CONNECTA_PLATFORM_TO_FORK_SECRET' => secret
                      ))
    allow(ActionCable.server).to receive(:broadcast)
    remote_connections = instance_double(ActionCable::RemoteConnections)
    remote_connection = instance_double(ActionCable::RemoteConnections::RemoteConnection, disconnect: true)
    allow(ActionCable.server).to receive(:remote_connections).and_return(remote_connections)
    allow(remote_connections).to receive(:where).and_return(remote_connection)
  end

  it 'epoch maior revoga com barreira local efetiva (broadcast + desconexao)' do
    revoke(account_id: account.id, chatwoot_user_id: agent_a.id, epoch: 2, revocation_id: SecureRandom.uuid)

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json['ack']['epoch']).to eq(2)
    record = Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id)
    expect(record.revoked_locally_at).not_to be_nil
    expect(ActionCable.server).to have_received(:broadcast)
      .with(agent_a.pubsub_token, hash_including(event: 'acl.revoked'))
  end

  it 'epoch igual com registro ainda ativo: ack so apos barreira local efetiva' do
    revoke(account_id: account.id, chatwoot_user_id: agent_a.id, epoch: 1, revocation_id: SecureRandom.uuid)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['ack']['epoch']).to eq(1)
    record = Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id)
    expect(record.epoch).to eq(1)
    expect(record.revoked_locally_at).not_to be_nil
    expect(ActionCable.server).to have_received(:broadcast)
  end

  it 'revogacao ja aplicada e idempotente: ack sem reescrever nem rebroadcast' do
    first_id = SecureRandom.uuid
    revoke(account_id: account.id, chatwoot_user_id: agent_a.id, epoch: 2, revocation_id: first_id)
    expect(response).to have_http_status(:ok)
    revoked_at = Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).revoked_locally_at

    revoke(account_id: account.id, chatwoot_user_id: agent_a.id, epoch: 2, revocation_id: SecureRandom.uuid)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['ack']['epoch']).to eq(2)
    expect(Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).revoked_locally_at.to_i).to eq(revoked_at.to_i)
    # O spy acumula: a 1ª revogação fez 1 broadcast; a 2ª não pode acrescentar nenhum.
    expect(ActionCable.server).to have_received(:broadcast).once
  end

  it 'epoch menor nao rebaixa nem reativa' do
    revoke(account_id: account.id, chatwoot_user_id: agent_a.id, epoch: 3, revocation_id: SecureRandom.uuid)
    expect(response).to have_http_status(:ok)

    revoke(account_id: account.id, chatwoot_user_id: agent_a.id, epoch: 2, revocation_id: SecureRandom.uuid)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['ack']['epoch']).to eq(3)
    record = Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id)
    expect(record.epoch).to eq(3)
    expect(record.revoked_locally_at).not_to be_nil
  end

  it 'account divergente responde 403' do
    revoke(account_id: account.id + 1, chatwoot_user_id: agent_a.id, epoch: 2, revocation_id: SecureRandom.uuid)

    expect(response).to have_http_status(:forbidden)
  end
end
