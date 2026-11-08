require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_transfer_schema'

# Micro passo 3: percurso completo create -> admit -> active -> primeira mensagem UMA VEZ.
# WP é stub de fronteira (PlatformClient#post); SUT é real: controller aninhado,
# ManualAdmissionTransaction, ScopeActivationService, MessageBuilder e dispatch guard.
# Sem rede, sem dados reais, só tabelas G0 sintéticas.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · admissão manual fim a fim (micro passo 3)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:admit_path) { "/api/v1/accounts/#{account.id}/conversations/connecta_manual_admission" }
  let(:destinations_path) { "#{admit_path}/destinations" }
  let(:wp_response) do
    {
      'status' => 'active', 'reused' => false, 'case_protocol' => 'BND00000001',
      'session_ref' => '777', 'case_version' => 1, 'org_unit_id' => org_a.id.to_s
    }
  end

  # Contato WhatsApp sem cadastro é válido (AC2): o source_id explícito é
  # o identificador roteável; o contato não precisa de phone_number.
  let!(:wa_contact) { create(:contact, account: account) }

  # O boot de produção instala este after_create via Connecta::Runtime::Installer;
  # aqui ele é registrado só para este spec e removido ao final (sem vazar para os
  # demais arquivos do mesmo processo).
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
    stub_const('ENV', ENV.to_h.merge('CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s,
                                     'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    allow(Redis::Alfred).to receive(:lpush)
    allow(Redis::Alfred).to receive(:lrem)
    allow(Redis::Alfred).to receive(:delete)
    client = instance_double(Connecta::Runtime::PlatformClient)
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(client).to receive(:get).and_return({ 'eligible_org_units' => [{ 'id' => org_a.id.to_s, 'name' => 'Setor A' }] })
    allow(client).to receive(:post).and_return(wp_response)
  end

  it 'membro do setor inicia e envia UMA mensagem após active real' do
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    post admit_path,
         params: { inbox_id: whatsapp_inbox.id, contact_id: wa_contact.id, source_id: source,
                   org_unit_id: org_a.id.to_s, message: { content: 'olá, sou do setor A' },
                   idempotency_key: 'attempt-1' },
         headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:created)
    created = Conversation.order(:id).last
    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: created.id)
    expect(scope).to have_attributes(state: 'active', case_version: 1, case_protocol: 'BND00000001')
    messages = Message.where(conversation_id: created.id, message_type: :outgoing)
    expect(messages.count).to eq(1)
    expect(messages.first.content).to include('olá, sou do setor A')
  end

  it 'double-click com mesmo nonce não duplica a primeira mensagem' do
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    payload = { inbox_id: whatsapp_inbox.id, contact_id: wa_contact.id, source_id: source,
                org_unit_id: org_a.id.to_s, message: { content: 'tentativa única' }, idempotency_key: 'dup-1' }
    2.times do
      post admit_path, params: payload, headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok).or have_http_status(:created)
    end

    created = Conversation.order(:id).last
    expect(Message.where(conversation_id: created.id, message_type: :outgoing).count).to eq(1)
  end

  it 'dois nonces distintos na mesma conversa criam duas mensagens, preservando caso e setor' do
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    base = { inbox_id: whatsapp_inbox.id, contact_id: wa_contact.id, source_id: source,
             org_unit_id: org_a.id.to_s }

    post admit_path, params: base.merge(message: { content: 'primeira' }, idempotency_key: 'nonce-a'),
                     headers: agent_a.create_new_auth_token
    first = Conversation.order(:id).last
    expect(response).to have_http_status(:created)

    post admit_path, params: base.merge(message: { content: 'segunda' }, idempotency_key: 'nonce-b'),
                     headers: agent_a.create_new_auth_token
    expect(response).to have_http_status(:ok)

    expect(Conversation.where(inbox: whatsapp_inbox, contact: wa_contact).count).to eq(1)
    expect(Conversation.order(:id).last.id).to eq(first.id)
    expect(first.reload.messages.where(message_type: :outgoing).order(:id).pluck(:content))
      .to contain_exactly('primeira', 'segunda')
    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: first.id)
    expect(scope).to have_attributes(state: 'active', case_protocol: 'BND00000001', case_version: 1)
    expect(scope.org_unit_id).to eq(org_a.id)
  end

  it 'payload adulterado não cria mensagem incoming/private nem troca o autor' do
    other = create(:user, account: account, role: :agent)
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"

    post admit_path,
         params: { inbox_id: whatsapp_inbox.id, contact_id: wa_contact.id, source_id: source,
                   org_unit_id: org_a.id.to_s,
                   message: { content: 'texto', message_type: 'incoming', private: true,
                              sender_type: 'AgentBot', sender_id: other.id },
                   idempotency_key: 'tamper-1' },
         headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:created)
    message = Message.where(message_type: :outgoing).order(:id).last
    expect(message).to be_present
    expect(message).not_to be_private
    expect(message.sender).to eq(agent_a)
  end

  it 'aceita anexo multipart nativo na primeira mensagem' do
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    upload = Rack::Test::UploadedFile.new('spec/assets/avatar.png', 'image/png')

    post admit_path,
         params: { inbox_id: whatsapp_inbox.id, contact_id: wa_contact.id, source_id: source,
                   org_unit_id: org_a.id.to_s,
                   message: { content: 'com anexo', attachments: [upload] },
                   idempotency_key: 'attach-1' },
         headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:created)
    message = Message.where(message_type: :outgoing).order(:id).last
    expect(message.attachments.count).to eq(1)
  end

  it 'recusa signed id solto em attachments sem criar mensagem' do
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    blob = get_blob_for('spec/assets/avatar.png', 'image/png')

    expect do
      post admit_path,
           params: { inbox_id: whatsapp_inbox.id, contact_id: wa_contact.id, source_id: source,
                     org_unit_id: org_a.id.to_s,
                     message: { content: 'signed', attachments: [blob.signed_id] },
                     idempotency_key: 'signed-1' },
           headers: agent_a.create_new_auth_token
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Conversation.where(inbox: whatsapp_inbox, contact: wa_contact).count).to eq(0)
  end

  it 'destinos lista só unidades ATENDER do ator (WP stub) e exige inbox show?' do
    get destinations_path, params: { inbox_id: whatsapp_inbox.id }, headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['eligible_org_units'].map { |u| u['id'] }).to eq([org_a.id.to_s])
  end

  it 'admin sem setor não ganha acesso: WP 403 vira 403 sem criar conversa' do
    client = Connecta::Runtime::PlatformClient.new
    allow(client).to receive(:post).and_raise(Connecta::Runtime::PlatformClient::Error.new('forbidden', status: :forbidden))
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    expect do
      post admit_path,
           params: { inbox_id: whatsapp_inbox.id, contact_id: wa_contact.id, source_id: source,
                     org_unit_id: org_b.id.to_s },
           headers: admin_nominal_unused.create_new_auth_token
    end.not_to change(Conversation, :count)

    expect(response).to have_http_status(:forbidden)
  end

  def admin_nominal_unused
    @admin_nominal_unused ||= create(:user, account: account, role: :agent).tap do |user|
      create(:inbox_member, inbox: whatsapp_inbox, user: user)
    end
  end
end
