require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_scope_schema'

# T0.2-c6 (spike G0): team_id proibido em inbox marcada e contact.deleted com snapshot.
# Rotas reais (config/routes.rb:147-193,256-291): update (PATCH/PUT conversations/:id),
# assignments (POST conversations/:conversation_id/assignments), bulk (POST bulk_actions),
# contacts destroy (DELETE contacts/:id, bloqueado para vinculado e por isso fora do caminho feliz).
# Hooks reais: ConversationHttpHook (write_guard -> team_guard 422), BulkHook (422 antes de enfileirar),
# ContactLifecycleHook (snapshot pré-destroy) + SocketHook (consome snapshot no contact.deleted).
# Gate NUNCA desligado. Nenhum exemplo executado aqui (ruby -c apenas); prova funcional pendente.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# rubocop:disable RSpec/MultipleDescribes
RSpec.describe 'Connecta G0 · team_id e contact.deleted (T0.2-c6)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:bulk_path) { "/api/v1/accounts/#{account.id}/bulk_actions" }
  let(:contacts_path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:conv_a_path) { "#{conversations_path}/#{conv_a.display_id}" }
  let(:conv_control_path) { "#{conversations_path}/#{conv_control.display_id}" }
  let(:assign_a_path) { "#{conv_a_path}/assignments" }
  let(:assign_control_path) { "#{conv_control_path}/assignments" }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_no_grant) { member_without_grant.create_new_auth_token }
  let!(:team_a) { Team.create!(name: 'Equipe A', account: account, allow_auto_assign: false) }

  # Isolamento local de atribuição: o MockRedis do ambiente de teste não aceita
  # `lpush` com array (`inbox_round_robin_service.rb:11` via
  # `ensure_assignee_is_from_team`/`run_auto_assignment`). Desliga SÓ a atribuição
  # automática nestes specs (inbox + equipe), sem mockar Gate/Controller/SocketHook
  # nem mudar a lógica de team_id verificada (422/404/200 preservados).
  # Sem isso, o setup real (`conv.update!(team:)` / factory `create(:conversation)`)
  # tenta consultar a fila vazia e quebra antes da autorização ser exercida.
  before do
    whatsapp_inbox.update!(enable_auto_assignment: false)
    control_inbox.update!(enable_auto_assignment: false)
  end

  describe 'rotas reais (não confundir 404 de rota com 404/403 de ACL)' do
    it 'update, assignments e bulk existem nas rotas reais' do
      expect(Rails.application.routes.recognize_path(conv_a_path, method: :patch))
        .to include(controller: 'api/v1/accounts/conversations', action: 'update')
      expect(Rails.application.routes.recognize_path(assign_a_path, method: :post))
        .to include(controller: 'api/v1/accounts/conversations/assignments', action: 'create')
      expect(Rails.application.routes.recognize_path(bulk_path, method: :post))
        .to include(controller: 'api/v1/accounts/bulk_actions', action: 'create')
    end
  end

  describe 'update com team_id (PATCH conversations/:id, rota real)' do
    it 'ator autorizado com team_id no topo nega 422 sem mudar team' do
      original_team_id = conv_a.reload.team_id

      patch conv_a_path, params: { team_id: team_a.id }, headers: token_a, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Team assignment is not allowed')
      expect(conv_a.reload.team_id).to eq(original_team_id)
      expect(Connecta::Scope::AccessAudit.exists?(access_path: 'conversation_update_team', decision: 'deny')).to be(true)
    end

    it 'null, mesmo valor e aninhado também são tentativa (422) sem gravar' do
      conv_a.update!(team: team_a)

      patch conv_a_path, params: { team_id: nil }, headers: token_a, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(conv_a.reload.team_id).to eq(team_a.id)

      patch conv_a_path, params: { team_id: team_a.id }, headers: token_a, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(conv_a.reload.team_id).to eq(team_a.id)

      patch conv_a_path, params: { conversation: { team_id: team_a.id } }, headers: token_a, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(conv_a.reload.team_id).to eq(team_a.id)
    end

    it 'fora do escopo não ganha acesso (404), sem mudar team' do
      patch conv_a_path, params: { team_id: team_a.id }, headers: token_b, as: :json

      expect(response).to have_http_status(:not_found)
      expect(conv_a.reload.team_id).to be_nil
    end

    it 'controle: inbox não marcada conserva nativo (ignora team_id, sem 422)' do
      patch conv_control_path, params: { team_id: team_a.id }, headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(conv_control.reload.team_id).to be_nil
    end
  end

  describe 'atribuição com team_id (POST assignments, rota real)' do
    it 'ator autorizado com team_id nega 422 sem mudar team' do
      post assign_a_path, params: { team_id: team_a.id }, headers: token_a, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Team assignment is not allowed')
      expect(conv_a.reload.team_id).to be_nil
    end

    it 'null, mesmo valor e aninhado também negam 422 sem gravar' do
      conv_a.update!(team: team_a)

      post assign_a_path, params: { team_id: nil }, headers: token_a, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post assign_a_path, params: { team_id: team_a.id }, headers: token_a, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post assign_a_path, params: { assignment: { team_id: team_a.id } }, headers: token_a, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(conv_a.reload.team_id).to eq(team_a.id)
    end

    it 'fora do escopo não ganha acesso (404), sem mudar team' do
      post assign_a_path, params: { team_id: team_a.id }, headers: token_no_grant, as: :json

      expect(response).to have_http_status(:not_found)
      expect(conv_a.reload.team_id).to be_nil
    end

    it 'controle: inbox não marcada conserva nativo (atribui team)' do
      post assign_control_path, params: { team_id: team_a.id }, headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(conv_control.reload.team_id).to eq(team_a.id)
    end
  end

  describe 'lote com team_id (POST bulk_actions, rota real)' do
    it 'ator autorizado com team_id em fields nega 422 sem enfileirar nem mudar' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id], fields: { team_id: team_a.id } },
                        headers: token_a, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conv_a.reload.team_id).to be_nil
    end

    it 'null, mesmo valor e aninhado em fields também negam 422 sem enfileirar' do
      conv_a.update!(team: team_a)

      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id], fields: { team_id: nil } },
                        headers: token_a, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)
      expect(response).to have_http_status(:unprocessable_entity)

      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id], fields: { team_id: team_a.id } },
                        headers: token_a, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)
      expect(response).to have_http_status(:unprocessable_entity)

      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id], fields: { nested: { team_id: team_a.id } } },
                        headers: token_a, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(conv_a.reload.team_id).to eq(team_a.id)
    end

    it 'misto marcado+desmarcado com team_id nega 422, nada enfileirado, nada muda' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id, conv_control.display_id],
                                  fields: { team_id: team_a.id } }, headers: token_a, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conv_a.reload.team_id).to be_nil
      expect(conv_control.reload.team_id).to be_nil
    end

    it 'controle: só desmarcado com team_id segue nativo (enfileira, sem 422)' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_control.display_id], fields: { status: 'resolved' } },
                        headers: token_a, as: :json
      end.to have_enqueued_job(BulkActionsJob)

      expect(response).to have_http_status(:ok)
    end

    it 'fora do escopo não ganha acesso (404), sem enfileirar nem mudar' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id], fields: { team_id: team_a.id } },
                        headers: token_b, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)

      expect(response).to have_http_status(:not_found)
      expect(conv_a.reload.team_id).to be_nil
    end
  end
end

RSpec.describe ActionCableListener do # nome fixado pelo T0.2-c6 (team+contato)
  include_context 'with connecta g0 scope fixture'

  let(:listener) { described_class.instance }
  let(:snapshot_key) { Connecta::Scope::ContactLifecycleHook::CONTACT_SNAPSHOT_KEY }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }

  # Mesmo isolamento da parte request: só desliga a atribuição automática local
  # (inbox física), sem mockar Gate/listener/SocketHook nem mudar o contrato de
  # team_id/snapshot verificado. Sem isso, a factory `create(:conversation)` roda
  # `run_auto_assignment` → round-robin e quebra no `lpush` do MockRedis antes de
  # qualquer asserção de contato.
  before do
    ActiveSupport::IsolatedExecutionState[snapshot_key] = nil
    whatsapp_inbox.update!(enable_auto_assignment: false)
    control_inbox.update!(enable_auto_assignment: false)
  end

  after { ActiveSupport::IsolatedExecutionState[snapshot_key] = nil }

  # Agrupamento da matriz c6 (team_id + contact.deleted, caminhos request + listener):
  # o cop RSpec/MultipleDescribes pede um único grupo de topo; unir os dois blocos
  # reduziria a clareza (contratos distintos: rotas HTTP vs listener ActionCable) sem
  # mudar autorização/contagem/efeito.
  # Ordenação de tokens: `match_array` abaixo (ordem irrelevante) preserva o contrato
  # (mesmo conjunto de destinatários), sem mudar autorização/contagem/efeito.
  def broadcast_tokens
    clear_enqueued_jobs
    yield
    enqueued_jobs.flat_map { |job| ActiveJob::Arguments.deserialize(job[:args]).first }
  end

  # Carga real que o Contact#dispatch_destroy_event envia (push_event_data + account_id).
  def deleted_contact_data(contact)
    contact.push_event_data.merge(account_id: account.id)
  end

  # Contato vinculado à inbox marcada e visível a agent_a (atender) e manager_a (acompanhar).
  # A factory de conversa cria o ContactInbox marcado; o escopo torna o contato visível no setor A.
  def create_marked_linked_contact!(protocol: 'CASO-X')
    linked = create(:contact, account: account)
    conv = create(:conversation, account: account, inbox: whatsapp_inbox, contact: linked)
    Connecta::Scope::ConversationScope.create!(conversation_id: conv.id, inbox_id: whatsapp_inbox.id, contact_id: linked.id,
                                               org_unit: org_a, state: 'active', case_protocol: protocol, case_version: 1)
    linked
  end

  describe 'contact.deleted com vínculo marcado (caminho real com snapshot)' do
    it 'destroy real captura snapshot com destinatários autorizados, sem PII no snapshot' do
      linked = create_marked_linked_contact!
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      linked.destroy!

      snapshot = ActiveSupport::IsolatedExecutionState[snapshot_key]
      expect(snapshot).to include(contact_id: linked.id, account_id: account.id)
      expect(snapshot.keys).to contain_exactly(:contact_id, :account_id, :tokens)
      expect(snapshot[:tokens]).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token)
    end

    it 'broadcast após vínculo apagado usa snapshot, sem stream da conta, e consome' do
      linked = create_marked_linked_contact!(protocol: 'CASO-Y')
      contact_id = linked.id
      contact_data = deleted_contact_data(linked)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      linked.destroy!
      snapshot_tokens = ActiveSupport::IsolatedExecutionState[snapshot_key][:tokens]

      # Corrida real: destroy_async já apagou o vínculo ao broadcast (só local, sem rede).
      ContactInbox.where(contact_id: contact_id).delete_all
      expect(ContactInbox.exists?(contact_id: contact_id, inbox_id: [whatsapp_inbox.id])).to be(false)

      event = Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data)
      tokens = broadcast_tokens { listener.contact_deleted(event) }

      expect(tokens).to match_array(snapshot_tokens)
      expect(tokens).not_to include("account_#{account.id}")
      expect(tokens).not_to include(agent_b.pubsub_token, member_without_grant.pubsub_token)
      expect(tokens).not_to include(admin_nominal.pubsub_token, native_admin.pubsub_token)
      expect(ActiveSupport::IsolatedExecutionState[snapshot_key]).to be_nil
    end

    it 'admin nominal e nativo ficam fora do snapshot (contrato: sem conteúdo para admin)' do
      linked = create_marked_linked_contact!(protocol: 'CASO-Z')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      linked.destroy!

      snapshot = ActiveSupport::IsolatedExecutionState[snapshot_key]
      expect(snapshot[:tokens]).not_to include(admin_nominal.pubsub_token, native_admin.pubsub_token)
    end
  end

  describe 'controles de contact.deleted' do
    it 'sem vínculo marcado não guarda snapshot e segue no stream da conta (nativo)' do
      unmarked = create(:contact, account: account)
      create(:contact_inbox, contact: unmarked, inbox: control_inbox)
      create(:conversation, account: account, inbox: control_inbox, contact: unmarked)
      contact_data = deleted_contact_data(unmarked)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      unmarked.destroy!

      expect(ActiveSupport::IsolatedExecutionState[snapshot_key]).to be_nil

      event = Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data)
      expect(broadcast_tokens { listener.contact_deleted(event) }).to contain_exactly("account_#{account.id}")
    end

    it 'misto marcado+desmarcado usa snapshot marcado, sem stream da conta' do
      linked = create_marked_linked_contact!(protocol: 'CASO-M')
      create(:contact_inbox, contact: linked, inbox: control_inbox)
      contact_id = linked.id
      contact_data = deleted_contact_data(linked)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      linked.destroy!
      snapshot_tokens = ActiveSupport::IsolatedExecutionState[snapshot_key][:tokens]
      expect(snapshot_tokens).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token)

      ContactInbox.where(contact_id: contact_id).delete_all

      event = Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data)
      tokens = broadcast_tokens { listener.contact_deleted(event) }

      expect(tokens).to match_array(snapshot_tokens)
      expect(tokens).not_to include("account_#{account.id}")
    end

    it 'destruição e broadcast locais não tocam rede (jobs locais, Gate ligado)' do
      linked = create_marked_linked_contact!(protocol: 'CASO-N')
      contact_data = deleted_contact_data(linked)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      linked.destroy!
      ContactInbox.where(contact_id: linked.id).delete_all

      event = Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data)
      broadcast_tokens { listener.contact_deleted(event) }

      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end
end
# rubocop:enable RSpec/MultipleDescribes
