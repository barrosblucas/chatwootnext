require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'

# Exclusão opt-in do Bot na fila humana (`exclude_active_bot=true`): partição
# positiva puramente local, sem rede. Nas inboxes marcadas só permanece
# atendimento corrente e roteado (escopo `active` do mesmo par, protocolo
# não-branco, unidade habilitada); recepção sem protocolo, protocolo commitido
# sem ativação local (`pending_activation` etc.) e legadas sem escopo somem
# desta visão; inboxes não-marcadas passam intactas. Linhas e contagens saem da
# mesma relação filtrada. Só a borda de banco pode falhar (preserva + flag).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · exclusão opt-in do Bot na fila humana', type: :request do
  let(:account) { create(:account) }
  let(:marked_inbox) { create(:inbox, account: account) }
  let(:control_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:bot_path) { "/api/v1/accounts/#{account.id}/conversations" }
  let(:meta_path) { "#{bot_path}/meta" }
  let(:org) { Connecta::Scope::OrgUnit.create!(name: 'Recepcao', path: '/recepcao/') }

  let!(:convs) do
    disabled = Connecta::Scope::OrgUnit.create!(name: 'Desativado', path: '/desativado/', enabled: false)
    built = {
      active_open: open_conversation!(marked_inbox),
      active_mine: open_conversation!(marked_inbox, assignee: agent),
      bot_reception: open_conversation!(marked_inbox),
      committed_not_active: open_conversation!(marked_inbox),
      pending_protocol: open_conversation!(marked_inbox),
      legacy: open_conversation!(marked_inbox),
      disabled_unit: open_conversation!(marked_inbox),
      closed_conv: open_conversation!(marked_inbox, status: :resolved),
      generic: open_conversation!(control_inbox)
    }
    put_scope!(built[:active_open], state: 'active', protocol: 'BND00000010', version: 1)
    put_scope!(built[:active_mine], state: 'active', protocol: 'BND00000011', version: 1)
    put_scope!(built[:bot_reception], state: 'reception', protocol: nil, version: 0)
    put_scope!(built[:committed_not_active], state: 'reception', protocol: 'BND00000012', version: 1)
    put_scope!(built[:pending_protocol], state: 'pending_activation', protocol: 'BND00000013', version: 0)
    put_scope!(built[:disabled_unit], state: 'active', protocol: 'BND00000014', version: 1, unit: disabled)
    put_scope!(built[:closed_conv], state: 'closed', protocol: 'BND00000015', version: 1)
    built
  end

  # Sem memoização: cada leitura reflete a resposta atual, nunca um corpo em cache.
  def json
    JSON.parse(response.body)
  end

  def bot_ids(payload = json['data']['payload'])
    Array(payload).map { |row| row['id'] }
  end

  def open_conversation!(target_inbox, status: :open, assignee: nil)
    contact = create(:contact, account: account)
    create(:conversation, account: account, inbox: target_inbox, contact: contact, status: status, assignee: assignee)
  end

  def put_scope!(conversation, state:, protocol:, version:, unit: nil)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
      org_unit: unit || org, state: state, case_protocol: protocol, case_version: version
    )
  end

  before do
    create(:inbox_member, inbox: marked_inbox, user: agent)
    create(:inbox_member, inbox: control_inbox, user: agent)
    Connecta::Scope::ScopedInbox.create!(inbox_id: marked_inbox.id, enforcement: 'enforce', maintenance: false)
    # Projeção utilizável do ator positivo (espelha g0_scope_fixture.rb:45-68):
    # heartbeat fresco, época de autenticação sem revogação e grant de leitura.
    Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current)
    Connecta::Scope::UserAuthEpoch.create!(user_id: agent.id, epoch: 1)
    Connecta::Scope::UserGrant.create!(user_id: agent.id, org_unit: org, permission: 'atender')
    allow(Connecta::Runtime::Feature).to receive(:enabled?).and_return(true)
    allow(Connecta::Runtime::PlatformClient).to receive(:new)
  end

  describe 'opt-in aplicado' do
    it 'partição positiva: só ativo roteado + genérica, contagem exata, sem rede', :aggregate_failures do
      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to contain_exactly(
        convs[:active_open].display_id, convs[:active_mine].display_id, convs[:generic].display_id
      )
      expect(json['data']['meta']).to include(
        'all_count' => 3, 'unassigned_count' => 2, 'mine_count' => 1,
        'assigned_count' => 1, 'bot_classification_unavailable' => false
      )
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end

    it 'meta opt-in conta sem o Bot e sem rede', :aggregate_failures do
      get meta_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['meta']).to include('all_count' => 3, 'bot_classification_unavailable' => false)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end

    it 'forma pré-protocolo reportada na #51 (aberta marcada sem protocolo) fica fora do humano, sem rede' do
      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).not_to include(convs[:bot_reception].display_id)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end

    it 'protocolo commitido sem ativação local não entra no humano (nem Bot)', :aggregate_failures do
      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids & [convs[:committed_not_active].display_id, convs[:pending_protocol].display_id]).to be_empty
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end

    it 'semântica normal de responsável sobre a partição', :aggregate_failures do
      get bot_path, params: { exclude_active_bot: 'true', assignee_type: 'unassigned' },
                    headers: agent.create_new_auth_token, as: :json
      expect(bot_ids).to contain_exactly(convs[:active_open].display_id, convs[:generic].display_id)

      get bot_path, params: { exclude_active_bot: 'true', assignee_type: 'me' },
                    headers: agent.create_new_auth_token, as: :json
      expect(bot_ids).to contain_exactly(convs[:active_mine].display_id)

      get bot_path, params: { exclude_active_bot: 'true', assignee_type: 'assigned' },
                    headers: agent.create_new_auth_token, as: :json
      expect(bot_ids).to contain_exactly(convs[:active_mine].display_id)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end

    it 'acima de 100 ativos: sem corte, sem rede, flag false', :aggregate_failures do
      contacts = Array.new(101) { create(:contact, account: account) }
      conversations = contacts.map do |contact|
        create(:conversation, account: account, inbox: marked_inbox, contact: contact)
      end
      rows = conversations.map do |conversation|
        { conversation_id: conversation.id, inbox_id: marked_inbox.id, contact_id: conversation.contact_id,
          org_unit_id: org.id, state: 'active', case_protocol: "BND#{conversation.id.to_s.rjust(8, '0')}",
          case_version: 1, created_at: Time.current, updated_at: Time.current }
      end
      # rubocop:disable Rails/SkipsModelValidations -- fileiras idênticas ao shape validado de put_scope! (create! nos demais exemplos); 101 factory creates só atrasariam o gate sem cobrir validação nova
      Connecta::Scope::ConversationScope.insert_all!(rows)
      # rubocop:enable Rails/SkipsModelValidations

      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['data']['meta']).to include('all_count' => 104, 'bot_classification_unavailable' => false)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end
  end

  describe 'visões não optadas nunca disparam lookup' do
    it 'sem opt-in a lista segue intacta, sem rede e sem a chave', :aggregate_failures do
      get bot_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to contain_exactly(
        convs[:active_open].display_id, convs[:active_mine].display_id, convs[:bot_reception].display_id,
        convs[:committed_not_active].display_id, convs[:generic].display_id
      )
      expect(json['data']['meta']['all_count']).to eq(5)
      expect(json['data']['meta'].key?('bot_classification_unavailable')).to be(false)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end

    it 'status=all com opt-in: inalterada e sem rede' do
      get bot_path, params: { exclude_active_bot: 'true', status: 'all' }, headers: agent.create_new_auth_token,
                    as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(convs[:closed_conv].display_id, convs[:bot_reception].display_id)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
      expect(json['data']['meta'].key?('bot_classification_unavailable')).to be(false)
    end

    it 'busca com opt-in: inalterada e sem rede' do
      get bot_path, params: { exclude_active_bot: 'true', q: 'triagem' }, headers: agent.create_new_auth_token,
                    as: :json

      expect(response).to have_http_status(:ok)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
      expect(json['data']['meta'].key?('bot_classification_unavailable')).to be(false)
    end

    it 'aba participating com opt-in: inalterada e sem rede' do
      get bot_path, params: { exclude_active_bot: 'true', conversation_type: 'participating' },
                    headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
      expect(json['data']['meta'].key?('bot_classification_unavailable')).to be(false)
    end
  end

  describe 'falha preserva a lista humana com sinal explícito' do
    it 'runtime desligado: sem rede, lista preservada, flag true', :aggregate_failures do
      allow(Connecta::Scope::BotEligibility).to receive(:available?).and_return(false)

      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(convs[:active_open].display_id, convs[:bot_reception].display_id,
                                 convs[:generic].display_id)
      expect(json['data']['meta']).to include('bot_classification_unavailable' => true)
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end

    it 'banco fora: lista original e flag true' do
      allow(Connecta::Scope::BotEligibility).to receive(:human_only)
        .and_raise(ActiveRecord::StatementInvalid.new('synthetic_db_failure'))

      get bot_path, params: { exclude_active_bot: 'true' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to include(convs[:active_open].display_id, convs[:bot_reception].display_id)
      expect(json['data']['meta']).to include('bot_classification_unavailable' => true)
    end

    it 'sem permissão: vazio exato, sem rede e sem vazar pares' do
      get bot_path, params: { exclude_active_bot: 'true' }, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(bot_ids).to be_empty
      expect(Connecta::Runtime::PlatformClient).not_to have_received(:new)
    end
  end

  describe '.exclude_from na relação (isola o SQL)' do
    it 'mantém só ativo corrente com protocolo e unidade habilitada; genérica intacta', :aggregate_failures do
      result = Connecta::Scope::BotEligibility.exclude_from(account.conversations)

      expect(result[:unavailable]).to be(false)
      expect(result[:relation].pluck(:id)).to contain_exactly(
        convs[:active_open].id, convs[:active_mine].id, convs[:generic].id
      )
    end

    it 'banco fora preserva a relação com flag, sem classificar incerto' do
      allow(Connecta::Scope::Projection).to receive(:marked_inbox_ids)
        .and_raise(ActiveRecord::StatementInvalid.new('synthetic_db_failure'))

      result = Connecta::Scope::BotEligibility.exclude_from(account.conversations)

      expect(result[:unavailable]).to be(true)
      expect(result[:relation].pluck(:id)).to include(convs[:bot_reception].id, convs[:legacy].id)
    end
  end
end
