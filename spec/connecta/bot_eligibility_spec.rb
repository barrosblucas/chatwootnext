require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'

# Fila Bot (servidor): lista e contagem dedicadas com elegibilidade confirmada
# pela plataforma, sem tocar a fila humana. Nenhum resultado de autorização é
# mockado; só a borda HTTP fork→WP é dublada (sem rede, sem segredo).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · fila Bot (bot-eligibility)', type: :request do
  let(:json) { JSON.parse(response.body) }
  let(:account) { create(:account) }
  let(:marked_inbox) { create(:inbox, account: account) }
  let(:control_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:bot_path) { "/api/v1/accounts/#{account.id}/conversations" }
  let(:client) { instance_double(Connecta::Runtime::PlatformClient) }

  let!(:org) { Connecta::Scope::OrgUnit.create!(name: 'Recepcao', path: '/recepcao/') }

  def bot_conversation!(target_account, target_inbox, status: :open)
    contact = create(:contact, account: target_account)
    create(:conversation, account: target_account, inbox: target_inbox, contact: contact, status: status)
  end

  def reception_scope!(conversation, protocol: nil, version: 0)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
      org_unit: org, state: 'reception', case_protocol: protocol, case_version: version
    )
  end

  let!(:bot_eligible) { bot_conversation!(account, marked_inbox) }
  let!(:bot_expired) { bot_conversation!(account, marked_inbox) }
  let!(:with_protocol) { bot_conversation!(account, marked_inbox) }
  let!(:resolved) { bot_conversation!(account, marked_inbox, status: :resolved) }
  let!(:generic) { bot_conversation!(account, control_inbox) }
  let!(:other_conv) { bot_conversation!(other_account, create(:inbox, account: other_account)) }

  before do
    create(:inbox_member, inbox: marked_inbox, user: agent)
    create(:inbox_member, inbox: control_inbox, user: agent)
    Connecta::Scope::ScopedInbox.create!(inbox_id: marked_inbox.id, enforcement: 'enforce', maintenance: false)
    # Projeção utilizável do ator positivo (espelha g0_scope_fixture.rb:45-68):
    # heartbeat fresco, época de autenticação sem revogação e grant de leitura.
    Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current)
    Connecta::Scope::UserAuthEpoch.create!(user_id: agent.id, epoch: 1)
    Connecta::Scope::UserGrant.create!(user_id: agent.id, org_unit: org, permission: 'atender')
    reception_scope!(bot_eligible)
    reception_scope!(bot_expired)
    reception_scope!(with_protocol, protocol: 'BND00000001', version: 1)
    reception_scope!(resolved)
    reception_scope!(other_conv)
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    # Caminho dedicado exige opt-in do runtime; os contextos de sucesso exercem
    # o guarda real como disponível, os de regressão forçam indisponível.
    allow(Connecta::Runtime::Feature).to receive(:enabled?).and_return(true)
    allow(client).to receive(:bot_eligibility).and_return(
      { 'eligible' => [{ 'inbox_id' => marked_inbox.id, 'conversation_id' => bot_eligible.id }] }
    )
  end

  def bot_ids(payload = json['data']['payload'])
    Array(payload).map { |row| row['id'] }
  end

  describe 'lista e contagem autorizadas' do
    it 'devolve só a linha confirmada pela plataforma, com contagem exata', :aggregate_failures do
      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      # A projeção do ator positivo é utilizável: sem isso a relação positiva
      # seria vazia por desenho e o 503 nunca seria exercido.
      expect(Connecta::Scope::Projection.new(agent).usable?).to be(true)
      expect(bot_ids).to contain_exactly(bot_eligible.display_id)
      expect(json['data']['meta']).to include('all_count' => 1, 'unassigned_count' => 1, 'mine_count' => 0, 'assigned_count' => 0)
    end

    it 'envia à plataforma só pares permitidos (sem vazamento de outra conta ou inbox genérica)', :aggregate_failures do
      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      # Só pares permitidos chegam à plataforma (sem vazamento de outra conta ou
      # inbox genérica): os dois candidatos sobrevivem ao filtro de escopo.
      expect(client).to have_received(:bot_eligibility).with(
        [
          { inbox_id: marked_inbox.id, conversation_id: bot_eligible.id },
          { inbox_id: marked_inbox.id, conversation_id: bot_expired.id }
        ]
      )
    end

    it 'agente sem inbox não vê nada e não dispara rede' do
      get bot_path, params: { conversation_type: 'bot' }, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to be_empty
      expect(json['data']['meta']).to include('all_count' => 0)
      expect(client).not_to have_received(:bot_eligibility)
    end

    it 'inbox genérica: vazio exato sem rede; fila humana segue com a linha de triagem expirada', :aggregate_failures do
      get bot_path, params: { conversation_type: 'bot', inbox_id: control_inbox.id },
                    headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to be_empty
      expect(client).not_to have_received(:bot_eligibility)

      get bot_path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_expired.display_id, generic.display_id, with_protocol.display_id)
    end

    it 'handoff atualiza na próxima observação (ponto no tempo, sem atomicidade)' do
      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json
      expect(bot_ids).to contain_exactly(bot_eligible.display_id)

      allow(client).to receive(:bot_eligibility).and_return(
        { 'eligible' => [{ 'inbox_id' => marked_inbox.id, 'conversation_id' => bot_expired.id }] }
      )

      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(bot_ids).to contain_exactly(bot_expired.display_id)
    end
  end

  describe 'falha fechada (503, nunca vazio parcial)' do
    it 'resposta fora do subconjunto enviado' do
      allow(client).to receive(:bot_eligibility).and_return(
        { 'eligible' => [{ 'inbox_id' => marked_inbox.id, 'conversation_id' => 999_999 }] }
      )

      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json['error']).to eq('bot_eligibility_unavailable')
    end

    it 'resposta duplicada' do
      allow(client).to receive(:bot_eligibility).and_return(
        { 'eligible' => [
          { 'inbox_id' => marked_inbox.id, 'conversation_id' => bot_eligible.id },
          { 'inbox_id' => marked_inbox.id, 'conversation_id' => bot_eligible.id }
        ] }
      )

      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json['error']).to eq('bot_eligibility_unavailable')
    end

    it 'resposta malformada' do
      allow(client).to receive(:bot_eligibility).and_return({ 'eligible' => 'ok' })

      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json['error']).to eq('bot_eligibility_unavailable')
    end

    it 'dependência fora (inclui cliente desconfigurado): 503 no Bot, humana intacta', :aggregate_failures do
      allow(client).to receive(:bot_eligibility).and_raise(Connecta::Runtime::PlatformClient::Error.new('down'))

      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(json['error']).to eq('bot_eligibility_unavailable')

      get bot_path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_eligible.display_id, bot_expired.display_id)
    end

    it 'estouro acima de 300 candidatos' do
      contacts = Array.new(301) { create(:contact, account: account) }
      conversations = contacts.map do |contact|
        create(:conversation, account: account, inbox: marked_inbox, contact: contact)
      end
      rows = conversations.map do |conversation|
        { conversation_id: conversation.id, inbox_id: marked_inbox.id, contact_id: conversation.contact_id,
          org_unit_id: org.id, state: 'reception', case_protocol: nil, case_version: 0,
          created_at: Time.current, updated_at: Time.current }
      end
      Connecta::Scope::ConversationScope.insert_all!(rows)

      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json['error']).to eq('bot_eligibility_overflow')
      expect(client).not_to have_received(:bot_eligibility)
    end
  end

  describe 'runtime desligado/não instalado: dedicado falha fechado, geral intacta' do
    before { allow(Connecta::Scope::BotEligibility).to receive(:available?).and_return(false) }

    it 'index bot responde 503 e nunca a fila geral como elegível', :aggregate_failures do
      get bot_path, params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json['error']).to eq('bot_eligibility_unavailable')
      expect(json['data']).to be_nil
      expect(client).not_to have_received(:bot_eligibility)
    end

    it 'meta bot responde 503 na mesma guarda', :aggregate_failures do
      get "#{bot_path}/meta", params: { conversation_type: 'bot' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json['error']).to eq('bot_eligibility_unavailable')
    end

    it 'lista ordinária segue 200 com as linhas autorizadas' do
      get bot_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(bot_eligible.display_id, bot_expired.display_id)
    end
  end

  describe '.available? (prova real de filtragem segura)' do
    it 'falso com runtime desligado' do
      allow(Connecta::Runtime::Feature).to receive(:enabled?).and_return(false)

      expect(Connecta::Scope::BotEligibility.available?).to be(false)
    end

    it 'verdadeiro com runtime ligado e ramo instalado neste processo' do
      expect(Connecta::Scope::BotEligibility.available?).to be(true)
    end
  end
end
