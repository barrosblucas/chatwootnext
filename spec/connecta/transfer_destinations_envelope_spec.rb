require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Envelope de destinations: o WP devolve OBJETO
# { case_version, source_org_unit_id, destinations: [...], staff_user_id };
# a API fork extrai o array e expõe { destinations: [...] }.
# Regressão: PlatformClient stubado via HTTP (WebMock) no SHAPE REAL;
# nunca fixture que já vem desembrulhada (isso mascararia o bug).
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::G0ProductTables.install!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta runtime · envelope de transfer-destinations (objeto WP → array fork)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:destinations_path) do
    "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/connecta_transfer/destinations"
  end
  let(:wire_platform) { 'http://platform.wiremock' }
  let(:wire_secret) { 'dest-envelope-synthetic-secret' }
  let(:real_wp_payload) do
    {
      'case_version' => 1,
      'source_org_unit_id' => 'org-farmacia',
      'destinations' => [
        { 'id' => 'org-hospital', 'name' => 'Hospital' },
        { 'id' => 'org-recepcao', 'name' => 'Recepção' }
      ],
      'staff_user_id' => 42
    }
  end

  around do |example|
    tables = Connecta::Runtime::G0Adapter::TABLES
    previous = tables.keys.index_with(&:table_name)
    tables.each { |model, table| model.table_name = table }
    Connecta::Runtime::G0Adapter.install!
    begin
      example.run
    ensure
      previous.each { |model, table| model.table_name = table }
    end
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => account.id.to_s,
                        'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                        'CONNECTA_PLATFORM_URL' => wire_platform,
                        'CONNECTA_FORK_TO_PLATFORM_SECRET' => wire_secret
                      ))
    Connecta::UserGrant.create!(user_id: agent_a.id, org_unit_id: org_a.id, permission: 'transferir')
  end

  def stub_wp_destinations(payload)
    stub_request(:get, %r{attendance/v1/transfer-destinations}o)
      .to_return(status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'desembrulha objeto real do WP: destinations é array com os 2 destinos, sem aninhamento' do
    stub_wp_destinations(real_wp_payload)

    get destinations_path, headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    parsed = response.parsed_body
    aggregate_failures 'envelope desembrulhado' do
      expect(parsed.keys).to eq(['destinations'])
      expect(parsed['destinations']).to be_an(Array)
      expect(parsed['destinations'].size).to eq(2)
      expect(parsed['destinations'].map { |d| d['name'] }).to eq(%w[Hospital Recepção])
      expect(parsed['destinations'].first).not_to have_key('destinations')
    end
  end

  it 'fallback seguro: WP sem destinations devolve array vazio, sem Hash/map error' do
    stub_wp_destinations({ 'case_version' => 1, 'source_org_unit_id' => 'org-farmacia' })

    get destinations_path, headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq({ 'destinations' => [] })
  end

  it 'fallback seguro: WP com destinations inválido (string) devolve array vazio' do
    stub_wp_destinations({ 'case_version' => 1, 'destinations' => 'Hospital' })

    get destinations_path, headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq({ 'destinations' => [] })
  end
end
