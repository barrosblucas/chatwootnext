require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF2 · campos privados do contato (spike G0): contato vinculado a inbox marcada
# expoe a ator escopado SOMENTE campos publicos; valores de custom_attributes
# globais e notas globais nunca chegam a leitor escopado.
# Contrato nativo (somente leitura aqui): `_contact.json.jbuilder:11`
# (custom_attributes), `get_contact_service.rb:12` + `contact_llm_formatter.rb:20`
# (attrs + notas), `ContactNotesHook` (notas 404/403), `Contact#push_event_data`
# (custom_attributes no socket) e `Message#push_event_data` (sender embutido).
# Guard RF5 sera instalado depois; esta spec usa API publica nativa
# (HTTP real + `enqueued_jobs`/`ActiveJob::Arguments.deserialize`), sem helpers RF5.
# Casos escritos em 2026-10-24 e NAO EXECUTADOS (runs na validacao consolidada).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · campos privados do contato (RF2)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:assistant) { create(:captain_assistant, account: account) }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_member) { member_without_grant.create_new_auth_token }
  let(:admin_user) { create(:user, account: account, role: :administrator) }
  let(:token_admin) { admin_user.create_new_auth_token }

  let(:contacts_path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:contact_a_path) { "#{contacts_path}/#{contact_a.id}" }
  let(:notes_a_path) { "#{contacts_path}/#{contact_a.id}/notes" }

  let(:secret_attr_key) { 'rf2_global_secret' }
  let(:secret_attr_value) { 'RF2-SENTINEL-ATTR-A' }
  let(:secret_note_body) { 'RF2-SENTINEL-NOTE-A' }
  let(:public_name_a) { 'RF2 Publico A' }

  # Contato de A com sentinela de outra situacao/setor: attrs globais secretos +
  # nota global + vinculo marcado (ContactInbox criado pelo factory de conversa).
  before do
    account.custom_attribute_definitions.find_or_create_by!(
      attribute_key: secret_attr_key, attribute_model: :contact_attribute
    ) do |definition|
      definition.attribute_display_name = 'RF2 Segredo'
      definition.attribute_display_type = :text
    end
    contact_a.update!(name: public_name_a, phone_number: '+5511999990001',
                      custom_attributes: { secret_attr_key => secret_attr_value })
    create(:note, account: account, contact: contact_a, user: agent_b, content: secret_note_body)
  end

  # Leitura crua do banco (nao usa getter potencialmente mascarado como prova).
  def raw_custom_attributes(contact)
    Contact.where(id: contact.id).pick(:custom_attributes)
  end

  def raw_note_contents(contact)
    Note.where(contact_id: contact.id, account_id: account.id).order(:id).pluck(:content)
  end

  # Payloads de broadcast capturados por token (listener + jobs nativos reais).
  def payloads_by_token
    clear_enqueued_jobs
    yield
    fixture_tokens = [agent_a.pubsub_token, agent_b.pubsub_token, manager_a.pubsub_token,
                      member_without_grant.pubsub_token]
    broadcast_jobs = [ActionCableBroadcastJob, Connecta::Scope::AdminMetadataBroadcastJob]
    enqueued_jobs.each_with_object({}) do |job, received|
      next unless broadcast_jobs.include?(job[:job])

      tokens, _event_name, payload = ActiveJob::Arguments.deserialize(job[:args])
      tokens.each { |token| received[token] = payload if fixture_tokens.include?(token) }
    end
  end

  it 'HTTP: ator A ve contato visivel com campos publicos, sem segredos globais' do
    get contact_a_path, headers: token_a

    expect(response).to have_http_status(:ok)
    expect(json.dig('payload', 'name')).to eq(public_name_a)
    expect(response.body).to include(public_name_a)
    expect(response.body).not_to include(secret_attr_value)
    expect(response.body).not_to include(secret_attr_key)
    expect(response.body).not_to include(secret_note_body)
  end

  it 'HTTP: membro e outro setor continuam negados, sem vazar segredos' do
    get contact_a_path, headers: token_b

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(secret_attr_value)
    expect(response.body).not_to include(secret_note_body)

    get contact_a_path, headers: token_member

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(secret_attr_value)
  end

  it 'HTTP: notas globais de contato vinculado nao vazam (404/403 nativo preservado)' do
    get notes_a_path, headers: token_a

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(secret_note_body)

    before_count = Note.where(contact_id: contact_a.id).count
    post notes_a_path, params: { note: { content: 'RF2 tentativa' } }, headers: token_a, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(Note.where(contact_id: contact_a.id).count).to eq(before_count)
  end

  it 'HTTP: escritas de attrs bloqueadas para escopado sem alterar dados do DB' do
    before_attrs = raw_custom_attributes(contact_a)
    before_notes = raw_note_contents(contact_a)

    update_params = { custom_attributes: { secret_attr_key => 'RF2-MUTADO' } }

    patch contact_a_path, params: update_params, headers: token_a, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(raw_custom_attributes(contact_a)).to eq(before_attrs)
    expect(raw_note_contents(contact_a)).to eq(before_notes)
  end

  describe 'ferramentas Copilot para ator A somente escopado' do
    it 'GetContact autorizado traz publicos, sem nota global nem attrs privados' do
      result = Captain::Tools::Copilot::GetContactService.new(assistant, user: agent_a)
                                                         .execute(contact_id: contact_a.id)

      expect(result).to include(public_name_a)
      expect(result).not_to include(secret_attr_value)
      expect(result).not_to include(secret_note_body)
    end

    it 'SearchContacts para A inclui alvo visivel sem segredos e mantem busca ampla RF1' do
      result = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_a)
                                                             .execute(name: public_name_a)

      expect(result).to include(public_name_a)
      expect(result).not_to include(secret_attr_value)
      expect(result).not_to include(secret_note_body)
    end
  end

  describe 'saida socket de contato marcado para leitores com escopo' do
    let(:listener) { ActionCableListener.instance }

    it 'contact.updated para escopado nao leva attrs globais, mesmo com autor admin' do
      event = Events::Base.new(:'contact.updated', Time.zone.now, contact: contact_a, performed_by: admin_user)
      received = payloads_by_token { listener.contact_updated(event) }

      expect(received.keys).to include(agent_a.pubsub_token)
      expect(received.keys).not_to include(agent_b.pubsub_token, member_without_grant.pubsub_token)
      scoped = received.fetch(agent_a.pubsub_token)
      expect(scoped.to_s).not_to include(secret_attr_value)
    end

    it 'update de conversa que recarrega SenderContact nao vaza segredos ao escopado' do
      message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: contact_a)
      event = Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conv_a)
      received = payloads_by_token { listener.conversation_updated(event) }

      expect(message.sender_id).to eq(contact_a.id)
      expect(received.keys).to include(agent_a.pubsub_token)
      scoped = received.fetch(agent_a.pubsub_token)
      expect(scoped.to_s).not_to include(secret_attr_value)
      expect(scoped.to_s).not_to include(secret_note_body)
    end
  end

  describe 'controles: unmarked e admin onde ja era autorizado' do
    it 'contato unmarked nativo preserva attrs/notas permitidos e DB intacto apos leituras' do
      contact_control.update!(custom_attributes: { secret_attr_key => 'RF2-LIVRE' })
      create(:note, account: account, contact: contact_control, user: agent_a, content: 'RF2 nota livre')
      before_attrs = raw_custom_attributes(contact_control)
      before_notes = raw_note_contents(contact_control)

      get "#{contacts_path}/#{contact_control.id}", headers: token_a

      expect(response).to have_http_status(:ok)
      expect(raw_custom_attributes(contact_control)).to eq(before_attrs)
      expect(raw_note_contents(contact_control)).to eq(before_notes)
    end

    it 'admin onde ja era autorizado preserva nativo, sem criar permissao nova' do
      get contact_a_path, headers: token_admin
      get notes_a_path, headers: token_admin

      expect(raw_custom_attributes(contact_a)).to include(secret_attr_key => secret_attr_value)
      expect(raw_note_contents(contact_a)).to include(secret_note_body)
    end
  end
end
