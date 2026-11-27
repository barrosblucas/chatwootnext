require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Reuso com Current.user nil (create da API pública de contato em inbox
# marcada como escopo Connecta). Antes do fix, o interceptor passava nil ao
# Gate e quebrava com NoMethodError em Projection#verified? (user.id); só
# chamar super sem reusar violaria o índice parcial (inbox, contato) com
# RecordNotUnique. O fix reusa a conversa aberta do par sem Gate nem
# auditoria e só cria quando não há escopo não-terminal.
RSpec.describe 'Connecta · interceptor do builder sem usuário logado', type: :request do
  let!(:account) { create(:account) }
  let!(:api_channel) { create(:channel_api, account: account) }
  let(:api_inbox) { api_channel.inbox }
  let!(:contact) { create(:contact, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox) }
  let!(:org_unit) { Connecta::Scope::OrgUnit.create!(name: 'Raiz', path: '/raiz/') }

  before do
    Connecta::Scope::ScopedInbox.create!(inbox_id: api_inbox.id, enforcement: 'enforce', maintenance: false)
  end

  def public_create_path(source_id)
    "/public/api/v1/inboxes/#{api_channel.identifier}/contacts/#{source_id}/conversations"
  end

  def create_open_conversation!(for_contact, for_contact_inbox, state: 'reception')
    conversation = create(:conversation, account: account, inbox: api_inbox, contact: for_contact,
                                         contact_inbox: for_contact_inbox)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: api_inbox.id, contact_id: for_contact.id,
      org_unit: org_unit, state: state, case_protocol: 'PUB-NIL', case_version: 0
    )
    conversation
  end

  it 'dois creates públicos para o par com escopo aberto reusam sem 500 (AC1)', :aggregate_failures do
    conversation = create_open_conversation!(contact, contact_inbox)

    expect do
      post public_create_path(contact_inbox.source_id)
      expect(response).to have_http_status(:success)
      first_id = response.parsed_body['id']
      expect(first_id).to eq(conversation.display_id)

      post public_create_path(contact_inbox.source_id)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(first_id)
    end.not_to change(Conversation, :count)
  end

  it 'par sem escopo aberto segue o fluxo nativo e cria (AC1)' do
    fresh = create(:contact, account: account)
    fresh_ci = create(:contact_inbox, contact: fresh, inbox: api_inbox)

    expect do
      post public_create_path(fresh_ci.source_id)
    end.to change(Conversation, :count).by(1)

    expect(response).to have_http_status(:success)
    created = api_inbox.conversations.find_by(display_id: response.parsed_body['id'])
    expect(created.contact_id).to eq(fresh.id)
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: created.id)).to be_nil
  end

  it 'Gate com usuário nil nega leitura e escrita sem exceção (AC2)' do
    conversation = create_open_conversation!(contact, contact_inbox)

    expect(Connecta::Scope::Gate.new(nil).read?(conversation, access_path: 'spec')).to be(false)
    expect(Connecta::Scope::Gate.new(nil).write?(conversation, access_path: 'spec')).to be(false)
  end

  it 'Gate com usuário nil não grava linha de auditoria (AC2)' do
    conversation = create_open_conversation!(contact, contact_inbox)

    expect do
      Connecta::Scope::Gate.new(nil).read?(conversation, access_path: 'spec')
      Connecta::Scope::Gate.new(nil).write?(conversation, access_path: 'spec')
    end.not_to change(Connecta::Scope::AccessAudit, :count)
  end

  it 'Projection com usuário nil nega sem exceção (AC2)' do
    projection = Connecta::Scope::Projection.new(nil)

    expect(projection.verified?).to be(false)
    expect(projection.usable?).to be(false)
    expect(projection.admin?).to be(false)
    expect(projection.granted_paths(%w[atender])).to eq([])
  end
end
