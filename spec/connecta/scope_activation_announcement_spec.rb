require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Ativação publica conversation.updated pós-commit pela via autorizada
# existente (sem payload/metadata novos) para a fila reconciliar sem clique:
# ScopeActivationService (admissão normal/transferência/reconciliação) e
# ManualAdmissionTransaction sem primeira mensagem. Só transição real anuncia;
# replay idempotente e rejeição (rollback) não anunciam.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta · anúncio pós-commit da ativação (fila sem clique)', type: :request do
  include ActiveJob::TestHelper
  include_context 'with connecta g0 scope fixture'

  let(:admit_path) { "/api/v1/accounts/#{account.id}/conversations/connecta_manual_admission" }
  let(:wp_response) do
    {
      'status' => 'active', 'reused' => false, 'case_protocol' => 'BND00000001',
      'session_ref' => '777', 'case_version' => 1, 'org_unit_id' => org_a.id.to_s
    }
  end

  # O boot de produção instala este after_create via Connecta::Runtime::Installer;
  # aqui ele é registrado só para este spec e removido ao final.
  around do |example|
    callback = proc do
      Connecta::Runtime::ReceptionScopeCreator.call(self) if Connecta::Runtime::Feature.enabled?
    end
    Conversation.after_create(callback)
    begin
      example.run
    ensure
      Conversation.skip_callback(:create, :after, callback)
    end
  end

  before do
    clear_enqueued_jobs
    allow(ActionCable.server).to receive(:broadcast)
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s,
                                     'CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s,
                                     'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    allow(Redis::Alfred).to receive(:lpush)
    allow(Redis::Alfred).to receive(:lrem)
    allow(Redis::Alfred).to receive(:delete)
    client = instance_double(Connecta::Runtime::PlatformClient)
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(client).to receive(:get).and_return({ 'eligible_org_units' => [{ 'id' => org_a.id.to_s, 'name' => 'Setor A' }] })
    allow(client).to receive(:post).and_return(wp_response)
  end

  after do
    clear_enqueued_jobs
  end

  def updated_jobs
    enqueued_jobs.select { |entry| entry[:job] == ActionCableBroadcastJob }.filter_map do |entry|
      tokens, event_name, payload = ActiveJob::Arguments.deserialize(entry[:args])
      next unless event_name == Events::Types::CONVERSATION_UPDATED

      [tokens, payload]
    end
  end

  def activate_scope(display_id, attrs)
    Connecta::Runtime::ScopeActivationService.new(conversation_id: display_id, attributes: attrs).call
  end

  def reception_attrs(state, **overrides)
    {
      'account_id' => account.id, 'expected_state' => state, 'org_unit_id' => org_a.id.to_s,
      'case_protocol' => 'CASO-A', 'session_ref' => 'sess-1', 'case_version' => 1
    }.merge(overrides.transform_keys(&:to_s))
  end

  it 'ativação reception anuncia conversation.updated só a leitores' do
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'reception', case_version: 0)
    clear_enqueued_jobs

    result = activate_scope(conv_a.display_id, reception_attrs('reception'))

    expect(result[:status]).to eq('activated')
    member_job = updated_jobs.find { |tokens, _payload| tokens.include?(agent_a.pubsub_token) }
    expect(member_job).not_to be_nil
    _tokens, payload = member_job
    expect(payload.stringify_keys['account_id']).to eq(account.id)
    announced = updated_jobs.flat_map(&:first)
    expect(announced).not_to include(member_without_grant.pubsub_token)
  end

  it 'replay idempotente não reanuncia' do
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'reception', case_version: 0)
    activate_scope(conv_a.display_id, reception_attrs('reception'))
    clear_enqueued_jobs

    result = activate_scope(conv_a.display_id, reception_attrs('reception'))

    expect(result[:status]).to eq('already_activated')
    expect(updated_jobs).to be_empty
  end

  it 'rejeição sem transição não anuncia e preserva o escopo' do
    Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'reception', case_version: 0)
    clear_enqueued_jobs

    expect do
      activate_scope(conv_a.display_id, reception_attrs('pending_activation'))
    end.to raise_error(Connecta::Runtime::ScopeActivationService::Conflict)

    expect(updated_jobs).to be_empty
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).state).to eq('reception')
  end

  it 'admissão manual sem mensagem ativa e anuncia sem criar mensagem' do
    contact = create(:contact, account: account)
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    clear_enqueued_jobs

    post admit_path,
         params: { inbox_id: whatsapp_inbox.id, contact_id: contact.id, source_id: source,
                   org_unit_id: org_a.id.to_s },
         headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:created)
    created = Conversation.order(:id).last
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: created.id).state).to eq('active')
    expect(Message.where(conversation_id: created.id).count).to eq(0)
    member_job = updated_jobs.find { |tokens, _payload| tokens.include?(agent_a.pubsub_token) }
    expect(member_job).not_to be_nil
    announced = updated_jobs.flat_map(&:first)
    expect(announced).not_to include(member_without_grant.pubsub_token)
  end

  it 'reuso manual idempotente não reanuncia' do
    contact = create(:contact, account: account)
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    payload = { inbox_id: whatsapp_inbox.id, contact_id: contact.id, source_id: source,
                org_unit_id: org_a.id.to_s }
    post admit_path, params: payload, headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:created)
    clear_enqueued_jobs

    post admit_path, params: payload, headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(updated_jobs).to be_empty
  end
end
