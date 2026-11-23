require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'

# Exclusão opt-in do Bot na fila humana (`exclude_active_bot=true`): remove só
# ids positivamente confirmados, antes de contagens e paginação, com orçamento
# HTTP total de ~1 s em lote único. Qualquer falha preserva a lista original e
# sinaliza `meta.bot_classification_unavailable`. Só a borda HTTP é dublada.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · exclusão opt-in do Bot na fila humana', type: :request do
  let(:json) { JSON.parse(response.body) }
  let(:account) { create(:account) }
  let(:marked_inbox) { create(:inbox, account: account) }
  let(:control_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:bot_path) { "/api/v1/accounts/#{account.id}/conversations" }
  let(:meta_path) { "#{bot_path}/meta" }
  let(:client) { instance_double(Connecta::Runtime::PlatformClient) }

  let!(:org) { Connecta::Scope::OrgUnit.create!(name: 'Recepcao', path: '/recepcao/') }

  def human_conversation!(target_inbox, status: :open)
    contact = create(:contact, account: account)
    create(:conversation, account: account, inbox: target_inbox, contact: contact, status: status)
  end

  def reception_scope!(conversation, protocol: nil, version: 0)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
      org_unit: org, state: 'reception', case_protocol: protocol, case_version: version
    )
  end

  let!(:bot_confirmed) { human_conversation!(marked_inbox) }
  let!(:bot_open) { human_conversation!(marked_inbox) }
  let!(:with_protocol) { human_conversation!(marked_inbox) }
  let!(:resolved) { human_conversation!(marked_inbox, status: :resolved) }
  let!(:generic) { human_conversation!(control_inbox) }

  before do
    create(:inbox_member, inbox: marked_inbox, user: agent)
    create(:inbox_member, inbox: control_inbox, user: agent)
    Connecta::Scope::ScopedInbox.create!(inbox_id: marked_inbox.id, enforcement: 'enforce', maintenance: false)
    reception_scope!(bot_confirmed)
    reception_scope!(bot_open)
    reception_scope!(with_protocol, protocol: 'BND00000001', version: 1)
    reception_scope!(resolved)
    allow(Connecta::Runtime::Feature).to receive(:enabled?).and_return(true)
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(client).to receive(:post).and_return({
                                                 'eligible' => [
                                                   { 'inbox_id' => marked_inbox.id, 'conversation_id' => bot_confirmed.id }
                                                 ]
                                               })
  end

  def bot_ids(payload = json['payload'])
    Array(payload).map { |row| row['id'] }
  end

  describe 'opt-in aplicado' do
    it 'exclui só o confirmado, com contagem exata e orçamento de 1 s em lote único', :aggregate_failures do
      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to contain_exactly(bot_open.display_id, with_protocol.display_id, generic.display_id)
      expect(json['meta']).to include('all_count' => 3, 'unassigned_count' => 3, 'bot_classification_unavailable' => false)
      expect(Connecta::Runtime::PlatformClient).to have_received(:new).with(timeout: 1)
      expect(client).to have_received(:post).once
    end

    it 'meta opt-in conta sem o confirmado', :aggregate_failures do
      get meta_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['meta']).to include('all_count' => 3, 'bot_classification_unavailable' => false)
    end

    it 'sem opt-in a lista segue intacta, sem rede e sem a chave', :aggregate_failures do
      get bot_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_confirmed.display_id, bot_open.display_id)
      expect(json['meta']['all_count']).to eq(4)
      expect(json['meta'].key?('bot_classification_unavailable')).to be(false)
      expect(client).not_to have_received(:post)
    end
  end

  describe 'visões não optadas nunca disparam lookup' do
    it 'status=all com opt-in: inalterada e sem rede' do
      get bot_path, params: { exclude_active_bot: 'true', status: 'all' }, headers: agent.create_new_auth_token,
                    as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_confirmed.display_id, resolved.display_id)
      expect(client).not_to have_received(:post)
      expect(json['meta'].key?('bot_classification_unavailable')).to be(false)
    end

    it 'busca com opt-in: inalterada e sem rede' do
      get bot_path, params: { exclude_active_bot: 'true', q: 'triagem' }, headers: agent.create_new_auth_token,
                    as: :json

      expect(response).to have_http_status(:ok)
      expect(client).not_to have_received(:post)
      expect(json['meta'].key?('bot_classification_unavailable')).to be(false)
    end

    it 'aba participating com opt-in: inalterada e sem rede' do
      get bot_path, params: { exclude_active_bot: 'true', conversation_type: 'participating' },
                    headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(client).not_to have_received(:post)
      expect(json['meta'].key?('bot_classification_unavailable')).to be(false)
    end
  end

  describe 'falha preserva a lista humana com sinal explícito' do
    it 'dependência fora: lista original e flag true', :aggregate_failures do
      allow(client).to receive(:post).and_raise(Connecta::Runtime::PlatformClient::Error.new('down'))

      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_confirmed.display_id, bot_open.display_id, generic.display_id)
      expect(json['meta']).to include('all_count' => 4, 'bot_classification_unavailable' => true)
    end

    it 'resposta fora do subconjunto: sem exclusão parcial, flag true', :aggregate_failures do
      allow(client).to receive(:post).and_return({
                                                   'eligible' => [{ 'inbox_id' => marked_inbox.id, 'conversation_id' => 999_999 }]
                                                 })

      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_confirmed.display_id)
      expect(json['meta']).to include('bot_classification_unavailable' => true)
    end

    it 'estouro acima de 100 candidatos: sem rede, lista preservada, flag true', :aggregate_failures do
      contacts = Array.new(101) { create(:contact, account: account) }
      conversations = contacts.map do |contact|
        create(:conversation, account: account, inbox: marked_inbox, contact: contact)
      end
      rows = conversations.map do |conversation|
        { conversation_id: conversation.id, inbox_id: marked_inbox.id, contact_id: conversation.contact_id,
          org_unit_id: org.id, state: 'reception', case_protocol: nil, case_version: 0,
          created_at: Time.current, updated_at: Time.current }
      end
      Connecta::Scope::ConversationScope.insert_all!(rows)

      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_confirmed.display_id)
      expect(json['meta']).to include('bot_classification_unavailable' => true)
      expect(client).not_to have_received(:post)
    end

    it 'runtime desligado: sem rede, lista preservada, flag true', :aggregate_failures do
      allow(Connecta::Scope::BotEligibility).to receive(:available?).and_return(false)

      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_confirmed.display_id, bot_open.display_id)
      expect(json['meta']).to include('bot_classification_unavailable' => true)
      expect(client).not_to have_received(:post)
    end

    it 'sem permissão: vazio exato, sem rede e sem vazar pares' do
      get bot_path, params: { exclude_active_bot: 'true' }, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to be_empty
      expect(client).not_to have_received(:post)
    end
  end
end
