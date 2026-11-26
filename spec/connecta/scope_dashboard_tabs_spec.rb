require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'

# Abas do dashboard Connecta (Correcao 02): contrato opt-in `connecta_dashboard=true`
# + `connecta_tab` (+ `connecta_org_unit_id` opcional) sobre a mesma inbox para
# dois setores autorizados (A, B) e um setor sem grant (C). Nenhuma decisao de
# autorizacao e mockada; so a borda HTTP fork->WP e dublada (sem rede).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · abas do dashboard (dashboard tabs)', type: :request do
  let(:account) { create(:account) }
  let(:marked_inbox) { create(:inbox, account: account) }
  let(:control_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:client) { instance_double(Connecta::Runtime::PlatformClient) }
  let(:tabs_path) { "/api/v1/accounts/#{account.id}/conversations" }
  let(:meta_path) { "#{tabs_path}/meta" }

  let!(:org_a) { Connecta::Scope::OrgUnit.create!(name: 'Setor A', path: '/setor-a/') }
  let!(:org_b) { Connecta::Scope::OrgUnit.create!(name: 'Setor B', path: '/setor-b/') }
  let!(:org_c) { Connecta::Scope::OrgUnit.create!(name: 'Setor C', path: '/setor-c/') }

  let!(:convs) do
    disabled = Connecta::Scope::OrgUnit.create!(name: 'Desativado', path: '/desativado/', enabled: false)
    built = {
      a_mine: open_conversation!(marked_inbox, assignee: agent),
      a_open: open_conversation!(marked_inbox),
      b_open: open_conversation!(marked_inbox),
      c_open: open_conversation!(marked_inbox),
      bot_row: open_conversation!(marked_inbox),
      blank_proto: open_conversation!(marked_inbox),
      nil_proto: open_conversation!(marked_inbox),
      disabled_row: open_conversation!(marked_inbox),
      pending_row: open_conversation!(marked_inbox),
      closed_row: open_conversation!(marked_inbox, status: :resolved),
      legacy_row: open_conversation!(marked_inbox),
      generic: open_conversation!(control_inbox)
    }
    put_scope!(built[:a_mine], unit: org_a, state: 'active', protocol: 'TAB00000001', version: 1)
    put_scope!(built[:a_open], unit: org_a, state: 'active', protocol: 'TAB00000002', version: 1)
    put_scope!(built[:b_open], unit: org_b, state: 'active', protocol: 'TAB00000003', version: 1)
    put_scope!(built[:c_open], unit: org_c, state: 'active', protocol: 'TAB00000004', version: 1)
    put_scope!(built[:bot_row], unit: org_a, state: 'reception', protocol: nil, version: 0)
    put_scope!(built[:blank_proto], unit: org_a, state: 'active', protocol: '   ', version: 1)
    put_scope!(built[:nil_proto], unit: org_a, state: 'active', protocol: nil, version: 1)
    put_scope!(built[:disabled_row], unit: disabled, state: 'active', protocol: 'TAB00000005', version: 1)
    put_scope!(built[:pending_row], unit: org_a, state: 'pending_activation', protocol: 'TAB00000006', version: 0)
    put_scope!(built[:closed_row], unit: org_a, state: 'closed', protocol: 'TAB00000007', version: 1)
    built
  end

  # Sem memoizacao: cada leitura reflete a resposta atual, nunca um corpo em cache.
  def json
    JSON.parse(response.body)
  end

  def tab_ids(payload = json['data']['payload'])
    Array(payload).map { |row| row['id'] }
  end

  def open_conversation!(target_inbox, status: :open, assignee: nil)
    contact = create(:contact, account: account)
    create(:conversation, account: account, inbox: target_inbox, contact: contact, status: status, assignee: assignee)
  end

  def put_scope!(conversation, unit:, state:, protocol:, version:)
    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
      org_unit: unit, state: state, case_protocol: protocol, case_version: version
    )
  end

  before do
    [agent, outsider, admin].each do |user|
      create(:inbox_member, inbox: marked_inbox, user: user)
      create(:inbox_member, inbox: control_inbox, user: user)
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    Connecta::Scope::ScopedInbox.create!(inbox_id: marked_inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current)
    Connecta::Scope::UserGrant.create!(user_id: agent.id, org_unit: org_a, permission: 'atender')
    Connecta::Scope::UserGrant.create!(user_id: agent.id, org_unit: org_b, permission: 'atender')
    allow(Connecta::Runtime::Feature).to receive(:enabled?).and_return(true)
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(client).to receive(:bot_eligibility).and_return(
      { 'eligible' => [{ 'inbox_id' => marked_inbox.id, 'conversation_id' => convs[:bot_row].id }] }
    )
  end

  def opt_in(tab, extra = {})
    { connecta_dashboard: 'true', connecta_tab: tab }.merge(extra)
  end

  # Sanitized failure context for selection assertions: active table and id
  # column type locate the failing layer (integer G0 vs UUID product) without
  # logging production data; only the fixture id class travels, never values.
  def scope_diag(fixture)
    'active_table=' \
      "#{Connecta::Scope::OrgUnit.table_name} " \
      "id_type=#{Connecta::Scope::OrgUnit.column_for_attribute('id').type} " \
      "fixture_id_class=#{fixture.id.class}"
  end

  describe 'minhas' do
    it 'lista so o atribuido ao agente no escopo, com sobreposicao triada permitida', :aggregate_failures do
      get tabs_path, params: opt_in('minhas'), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to contain_exactly(convs[:a_mine].display_id)
      expect(json['data']['meta']).to include('all_count' => 1, 'mine_count' => 1)
      expect(client).not_to have_received(:bot_eligibility)
    end

    it 'meta concorda com a lista (mesmo predicado, nao tamanho da pagina)', :aggregate_failures do
      get meta_path, params: opt_in('minhas'), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['meta']).to include('all_count' => 1, 'mine_count' => 1)
    end

    it 'sem opt-in o caminho nativo segue intacto', :aggregate_failures do
      get tabs_path, params: { assignee_type: 'me' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to contain_exactly(convs[:a_mine].display_id)
    end
  end

  describe 'aguardando' do
    it 'agrega os setores autorizados com triagem completa e sem responsável', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando'), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to contain_exactly(
        convs[:a_open].display_id, convs[:b_open].display_id, convs[:generic].display_id
      )
      expect(json['data']['meta']).to include('all_count' => 3)
      expect(client).not_to have_received(:bot_eligibility)
    end

    it 'exclui Bot, protocolo em branco/ausente, unidade desativada, pendente e legada', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando'), headers: agent.create_new_auth_token, as: :json

      expect(tab_ids & [
        convs[:bot_row].display_id, convs[:blank_proto].display_id, convs[:nil_proto].display_id,
        convs[:disabled_row].display_id, convs[:pending_row].display_id, convs[:legacy_row].display_id,
        convs[:c_open].display_id
      ]).to be_empty
    end

    it 'meta conta sem o Bot e sem rede', :aggregate_failures do
      get meta_path, params: opt_in('aguardando'), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['meta']).to include('all_count' => 3)
      expect(client).not_to have_received(:bot_eligibility)
    end

    it 'sem grant na inbox marcada nao ve nada do marcado', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando'), headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to be_empty
      expect(json['data']['meta']).to include('all_count' => 0)
    end
  end

  describe 'selecao de setor' do
    it 'estreita para o setor validado sem derivar acesso de inbox', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: org_a.id),
                     headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to contain_exactly(
        convs[:a_open].display_id, convs[:generic].display_id
      )
    end

    it 'setor nao autorizado falha fechado sem revelar existencia', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: org_c.id),
                     headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to be_empty
      expect(json['data']['meta']).to include('all_count' => 0)
    end

    it 'selecao inexistente ou malformada falha fechado igual a negada', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: 999_999),
                     headers: agent.create_new_auth_token, as: :json
      expect(tab_ids).to be_empty
      expect(json['data']['meta']).to include('all_count' => 0)

      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: 'abc'),
                     headers: agent.create_new_auth_token, as: :json
      expect(tab_ids).to be_empty
      expect(json['data']['meta']).to include('all_count' => 0)
    end

    it 'rejeita formas fora do decimal positivo/bigint e UUID sem agregar nem estourar', :aggregate_failures do
      diag = "#{scope_diag(org_a)} integer_schema=#{Connecta::Scope::OrgUnit.table_name == 'connecta_g0_org_units'}"
      ['0', '-5', '1.5', '0x10', '1e3', '+7', '99999999999999999999', 'not-a-uuid'].each do |bad|
        get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: bad),
                       headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok), "#{diag} raw_class=#{bad.class}"
        expect(tab_ids).to be_empty, "#{diag} raw_class=#{bad.class}"
        expect(json['data']['meta']).to include('all_count' => 0), "#{diag} raw_class=#{bad.class}"
      end
    end

    it 'UUID no schema inteiro falha fechado sem excecao (forma do outro schema)', :aggregate_failures do
      diag = scope_diag(org_a)
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: SecureRandom.uuid),
                     headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok), diag
      expect(tab_ids).to be_empty, diag
      expect(json['data']['meta']).to include('all_count' => 0), diag
    end

    it 'selecao em branco agrega como ausente (limpar restaura o agregado)', :aggregate_failures do
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: '   '),
                     headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok), scope_diag(org_a)
      expect(tab_ids).to contain_exactly(
        convs[:a_open].display_id, convs[:b_open].display_id, convs[:generic].display_id
      ), scope_diag(org_a)
    end
  end

  describe 'todos (admin ou gestor)' do
    it 'permite ao gestor ver conversas atribuídas no setor gerido' do
      Connecta::Scope::UserGrant.create!(user_id: outsider.id, org_unit: org_a, permission: 'gerir')
      get tabs_path, params: opt_in('todos'), headers: outsider.create_new_auth_token, as: :json

      expect(tab_ids).to include(convs[:a_mine].display_id)
      expect(tab_ids).not_to include(convs[:b_open].display_id)
    end

    it 'nega nao-admin sem vazar totais de badge', :aggregate_failures do
      get tabs_path, params: opt_in('todos'), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to be_empty
      expect(json['data']['meta']).to include('all_count' => 0, 'mine_count' => 0)

      get meta_path, params: opt_in('todos'), headers: agent.create_new_auth_token, as: :json
      expect(json['meta']).to include('all_count' => 0)
    end

    it 'admin ve todos os atendimentos humanos dos setores, sem linhas Bot', :aggregate_failures do
      get tabs_path, params: opt_in('todos'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to contain_exactly(
        convs[:a_mine].display_id, convs[:a_open].display_id, convs[:b_open].display_id,
        convs[:c_open].display_id, convs[:generic].display_id
      )
      expect(json['data']['meta']).to include('all_count' => 5)
    end

    it 'status resolved mostra o historico humano encerrado, nao a fila aberta', :aggregate_failures do
      get tabs_path, params: opt_in('todos', status: 'resolved'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to contain_exactly(convs[:closed_row].display_id)
    end

    it 'status all soma humanos abertos e encerrados', :aggregate_failures do
      get meta_path, params: opt_in('todos', status: 'all'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['meta']).to include('all_count' => 6)
    end
  end

  describe 'bot (admin-only, canonico do servidor)' do
    it 'nega nao-admin sem vazar totais', :aggregate_failures do
      get tabs_path, params: opt_in('bot'), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to be_empty
      expect(json['data']['meta']).to include('all_count' => 0)
      expect(client).not_to have_received(:bot_eligibility)
    end

    it 'admin ve so a linha confirmada pela plataforma, com contagem exata', :aggregate_failures do
      get tabs_path, params: opt_in('bot'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(tab_ids).to contain_exactly(convs[:bot_row].display_id)
      expect(json['data']['meta']).to include('all_count' => 1)
      expect(client).to have_received(:bot_eligibility)

      get meta_path, params: opt_in('bot'), headers: admin.create_new_auth_token, as: :json
      expect(json['meta']).to include('all_count' => 1)
    end
  end

  describe 'paginacao e caminho legado' do
    it 'totais exatos por predicado, nao por tamanho da pagina', :aggregate_failures do
      with_modified_env CONVERSATION_RESULTS_PER_PAGE: '1' do
        pages = (1..3).map do |page|
          get tabs_path, params: opt_in('aguardando').merge(page: page), headers: agent.create_new_auth_token, as: :json
          [JSON.parse(response.body).dig('data', 'payload').map { |row| row['id'] },
           JSON.parse(response.body).dig('data', 'meta', 'all_count')]
        end

        expect(pages.map(&:first).map(&:size)).to eq([1, 1, 1])
        expect(pages.map(&:first).flatten).to contain_exactly(
          convs[:a_open].display_id, convs[:b_open].display_id, convs[:generic].display_id
        )
        expect(pages.map(&:last).uniq).to eq([3])
      end
    end

    it 'sem inbox marcada o opt-in preserva o resultado nativo', :aggregate_failures do
      Connecta::Scope::ScopedInbox.delete_all

      get tabs_path, params: { assignee_type: 'me' }, headers: agent.create_new_auth_token, as: :json
      native_ids = tab_ids

      get tabs_path, params: opt_in('minhas'), headers: agent.create_new_auth_token, as: :json
      expect(tab_ids).to match_array(native_ids)
    end
  end

  describe 'selecao UUID no schema produto (runtime, tabelas connecta_*)' do
    # Mesmo mapa que o G0Adapter aplica em producao, so troca de tabelas sem
    # os hooks: o caminho admin do DashboardTabs nao passa pela Projection
    # (cujo granted_paths original e hardcoded nas tabelas G0), entao a troca
    # basta e nada global vaza para os outros exemplos (restaura as tabelas e
    # o column cache no ensure; dados sinteticos com rollback transacional).
    def pin_product_scope_tables
      {
        Connecta::Scope::OrgUnit => 'connecta_org_units',
        Connecta::Scope::ConversationScope => 'connecta_conversation_scopes',
        Connecta::Scope::ScopedInbox => 'connecta_scoped_inboxes',
        Connecta::Scope::UserGrant => 'connecta_user_grants',
        Connecta::Scope::UserAuthEpoch => 'connecta_user_auth_epochs',
        Connecta::Scope::AclSyncState => 'connecta_acl_sync_state'
      }
    end

    around do |example|
      mapping = pin_product_scope_tables
      previous = mapping.keys.index_with(&:table_name)
      mapping.each { |model, table| model.table_name = table }
      mapping.each_key(&:reset_column_information)
      begin
        example.run
      ensure
        previous.each { |model, table| model.table_name = table }
        previous.each_key(&:reset_column_information)
      end
    end

    it 'estreita a lista e a meta pelo setor UUID, com maiusculas normalizadas', :aggregate_failures do
      diag = scope_diag(org_a)
      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: org_a.id),
                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok), diag
      expect(tab_ids).to contain_exactly(
        convs[:a_open].display_id, convs[:generic].display_id
      ), diag
      expect(json['data']['meta']).to include('all_count' => 2), diag

      get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: org_a.id.upcase),
                     headers: admin.create_new_auth_token, as: :json
      expect(tab_ids).to contain_exactly(
        convs[:a_open].display_id, convs[:generic].display_id
      ), diag

      get meta_path, params: opt_in('aguardando', connecta_org_unit_id: org_a.id),
                     headers: admin.create_new_auth_token, as: :json
      expect(json['meta']).to include('all_count' => 2), diag
    end

    it 'UUID inexistente, inteiro e malformado falham fechado sem 500', :aggregate_failures do
      diag = scope_diag(org_a)
      [SecureRandom.uuid, '7', 'not-a-uuid'].each do |bad|
        get tabs_path, params: opt_in('aguardando', connecta_org_unit_id: bad),
                       headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok), "#{diag} raw_class=#{bad.class}"
        expect(tab_ids).to be_empty, "#{diag} raw_class=#{bad.class}"
        expect(json['data']['meta']).to include('all_count' => 0), "#{diag} raw_class=#{bad.class}"
      end
    end
  end
end
