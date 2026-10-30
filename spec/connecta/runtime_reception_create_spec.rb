require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# MICRO PASSO 1b: "Abrir existente (Recomendado)". Criação request real em
# inbox marcada COM o callback de recepção ativo (after_create do runtime).
# Par (inbox, contato) com atendimento não-terminal AUTORIZADO reutiliza a
# conversa existente (sem nova Conversation/scope, sem tocar o escopo alheio);
# sem acesso visível, bloqueia 403 sem vazar ID/dados e sem criar nada.
# Sem existente, cria nova com escopo reception (idempotente por conversa).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · criação com callback de recepção (micro passo 1)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:conversations_path) { "/api/v1/accounts/#{account.id}/conversations" }

  around do |example|
    # Registra o after_create do runtime só durante este spec e remove depois,
    # para não vazar o callback para outras specs do processo.
    callback = proc { Connecta::Runtime::ReceptionScopeCreator.call(self) }
    Conversation.after_create(callback)
    begin
      example.run
    ensure
      Conversation.skip_callback(:create, :after, callback)
    end
  end

  before do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))
    allow(Redis::Alfred).to receive(:lpush)
    allow(Redis::Alfred).to receive(:lrem)
    allow(Redis::Alfred).to receive(:delete)
  end

  it 'par com atendimento de A reutiliza a conversa existente sem criar nova' do # rubocop:disable RSpec/MultipleExpectations
    # Fixture cria conv_a (contact_a) com escopo active: o 1º POST deste teste
    # já cai no reuso. Usa contact_transferred (escopo transferred_out =
    # terminal, fora do índice parcial) para provar criação + reuso seguintes.
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    post conversations_path,
         params: { inbox_id: whatsapp_inbox.id, contact_id: contact_transferred.id, source_id: source, assignee_id: agent_a.id },
         headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    first = Conversation.order(:id).last
    first_scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: first.id)
    expect(first_scope).to have_attributes(state: 'reception', case_version: 0)

    source2 = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    expect do
      post conversations_path,
           params: { inbox_id: whatsapp_inbox.id, contact_id: contact_transferred.id, source_id: source2, assignee_id: agent_a.id },
           headers: agent_a.create_new_auth_token
    end.not_to change(Conversation, :count)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['id']).to eq(first.display_id)
    # Escopo alheio intacto: mesmo estado/versão, sem nova linha de escopo
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: first.id)).to have_attributes(
      state: 'reception', case_version: 0, id: first_scope.id
    )
    expect(Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id, contact_id: contact_transferred.id).count).to eq(2)
    expect(Message.where(conversation_id: first.id).count).to eq(0)
  end

  it 'atendimento existente de outro setor sem acesso bloqueia 403 sem vazar nem criar' do
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    expect do
      post conversations_path,
           params: { inbox_id: whatsapp_inbox.id, contact_id: contact_a.id, source_id: source, assignee_id: agent_a.id },
           headers: agent_b.create_new_auth_token
    end.not_to change(Conversation, :count)

    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(conv_a.display_id.to_s)
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id)).to have_attributes(
      state: 'active', case_version: 1
    )
  end

  it 'reuso com mensagem exige escrita: sem autoridade, 403 sem mensagem nem conversa' do
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    expect do
      post conversations_path,
           params: { inbox_id: whatsapp_inbox.id, contact_id: contact_a.id, source_id: source,
                     message: { content: 'ola' } },
           headers: manager_a.create_new_auth_token
    end.not_to change(Conversation, :count)

    expect(response).to have_http_status(:forbidden)
    expect(Message.where(conversation_id: conv_a.id).count).to eq(0)
  end

  it 'callback é idempotente por conversa: segunda chamada retorna o escopo sem duplicar' do
    fresh_contact = create(:contact, account: account)
    direct = create(:conversation, account: account, inbox: whatsapp_inbox, contact: fresh_contact)
    first_call = Connecta::Runtime::ReceptionScopeCreator.call(direct)
    expect(first_call).to have_attributes(state: 'reception', case_version: 0)

    expect do
      second_call = Connecta::Runtime::ReceptionScopeCreator.call(direct)
      expect(second_call.id).to eq(first_call.id)
    end.not_to change(Connecta::Scope::ConversationScope, :count)
  end

  # contact_b já tem atendimento active do agente B (fixture): agent_a não
  # tem leitura nele, então o reuso bloqueia. Usa contato fresco (sem escopo)
  # para provar criação + reuso autorizado do próprio autor.
  it 'conversa criada fica sem envio liberado: sem mensagem de saída sem ativação' do
    fresh = create(:contact, account: account)
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    post conversations_path,
         params: { inbox_id: whatsapp_inbox.id, contact_id: fresh.id, source_id: source, assignee_id: agent_a.id },
         headers: agent_a.create_new_auth_token

    expect(response).to have_http_status(:ok)
    created = Conversation.order(:id).last
    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: created.id)
    expect(scope.state).to eq('reception')
    expect(Message.where(conversation_id: created.id, message_type: :outgoing).count).to eq(0)
  end

  it 'dez criações sequenciais para o mesmo contato reutilizam a primeira sem 404' do
    fresh2 = create(:contact, account: account)
    before_count = Conversation.count
    first_internal_id = nil
    10.times do
      source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
      post conversations_path, params: { inbox_id: whatsapp_inbox.id, contact_id: fresh2.id, source_id: source,
                                         assignee_id: agent_a.id }, headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)
      got = Conversation.find_by!(account_id: account.id, display_id: JSON.parse(response.body)['id']).id
      first_internal_id ||= got
      expect(got).to eq(first_internal_id)
    end

    expect(Conversation.count - before_count).to eq(1)
    scopes = Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id, contact_id: fresh2.id)
    expect(scopes.count).to eq(1)
    expect(scopes.first).to have_attributes(state: 'reception', case_version: 0)
  end

  it 'source_id de outra conta continua negado sem criar nada' do
    other_account = create(:account)
    other_channel = build(:channel_whatsapp, account: other_account, provider: 'baileys')
    other_channel.save!(validate: false)
    other_inbox = build(:inbox, account: other_account, channel: other_channel, name: 'Outra')
    other_inbox.save!(validate: false)
    other_contact = create(:contact, account: other_account)
    other_ci = create(:contact_inbox, contact: other_contact, inbox: other_inbox)

    expect do
      post conversations_path, params: { source_id: other_ci.source_id }, headers: agent_a.create_new_auth_token
    end.not_to change(Conversation, :count)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'inbox não marcada continua sem escopo e sem erro' do
    expect do
      post conversations_path, params: { inbox_id: control_inbox.id, contact_id: contact_control.id },
                               headers: agent_a.create_new_auth_token
    end.to change(Conversation, :count).by(1)

    expect(response).to have_http_status(:ok)
    created = Conversation.order(:id).last
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: created.id)).to be_nil
  end
end
