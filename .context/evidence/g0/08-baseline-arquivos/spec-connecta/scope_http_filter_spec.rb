require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 parte B1 (spike G0): filtros avançados, superfícies HTTP de mensagens e criação de conversa na MESMA inbox marcada.
# Mesmo fixture da parte A. Políticas, queries e hooks são os reais; nenhum resultado de autorização é mockado.
# A única exceção é a verificação de que o serviço legado de transferência não é chamado (asserção de não-invocação).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · escopo HTTP de filtros, mensagens e criação (T0.2 parte B1)', type: :request do
  include_context 'with connecta g0 scope fixture'

  # Estados que agentes não leem (pending_activation, activation_stuck): o fixture da parte A não os cobre.
  # Criadas com assignee membro: sem ele, o auto-assignment roda o round-robin, que o MockRedis do ambiente de teste não aceita.
  let!(:contact_pending) { create(:contact, account: account) }
  let!(:contact_stuck) { create(:contact, account: account) }
  let!(:conv_pending) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_pending, assignee: agent_a) }
  let!(:conv_stuck) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_stuck, assignee: agent_a) }

  let!(:message_a) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a, message_type: :outgoing,
                     content: 'mensagem de A')
  end

  let(:filter_path) { "#{conversations_path}/filter" }
  let(:status_open) { [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'] }] }
  let(:messages_path) { "#{conversations_path}/#{conv_a.display_id}/messages" }

  before do
    Connecta::Scope::ConversationScope.create!(conversation_id: conv_pending.id, inbox_id: whatsapp_inbox.id, contact_id: contact_pending.id,
                                               org_unit: org_a, state: 'pending_activation', case_protocol: 'CASO-P', case_version: 1)
    Connecta::Scope::ConversationScope.create!(conversation_id: conv_stuck.id, inbox_id: whatsapp_inbox.id, contact_id: contact_stuck.id,
                                               org_unit: org_a, state: 'activation_stuck', case_protocol: 'CASO-S', case_version: 1)
  end

  describe 'filtro (POST conversations/filter): contagem e lista pela mesma relação escopada' do
    it 'agente A lista e conta só o próprio setor e o controle nativo' do
      post filter_path, params: { payload: status_open }, headers: agent_a.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['payload'].pluck('id')).to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_control.display_id)
      expect(json['meta']['all_count']).to eq(3)
    end

    it 'agente B não recebe a conversa de A em filtro composto com OR (o escopo vale para o conjunto inteiro)' do
      payload = [
        { attribute_key: 'display_id', filter_operator: 'equal_to', values: [conv_a.display_id], query_operator: 'OR' },
        { attribute_key: 'status', filter_operator: 'equal_to', values: ['open'] }
      ]
      post filter_path, params: { payload: payload }, headers: agent_b.create_new_auth_token, as: :json

      expect(json['payload'].pluck('id')).to contain_exactly(conv_b.display_id)
      expect(json['meta']['all_count']).to eq(1)
    end

    it 'agente B não encontra conversa de A por display_id, nem a conta' do
      post filter_path, params: { payload: [{ attribute_key: 'display_id', filter_operator: 'equal_to', values: [conv_a.display_id] }] },
                        headers: agent_b.create_new_auth_token, as: :json

      expect(json['payload']).to be_empty
      expect(json['meta']['all_count']).to eq(0)
    end

    it 'actor, setor e usuário forjados no corpo e nos cabeçalhos não ampliam o agente B' do
      post filter_path,
           params: { payload: status_open, actor_id: agent_a.id, org_unit_id: org_a.id, sector: 'A', user_id: agent_a.id },
           headers: agent_b.create_new_auth_token.merge('X-Connecta-Actor' => agent_a.id.to_s, 'X-Connecta-Org-Unit' => 'A'),
           as: :json

      expect(json['payload'].pluck('id')).to contain_exactly(conv_b.display_id)
      expect(json['meta']['all_count']).to eq(1)
    end

    it 'filtro salvo global criado pelo admin não amplia o acesso do agente A' do
      saved = CustomFilter.create!(account: account, user: admin_nominal, name: 'Só B', filter_type: :conversation, visibility: :global,
                                   query: { payload: [{ attribute_key: 'display_id', filter_operator: 'equal_to', values: [conv_b.display_id] }] })

      post filter_path, params: { payload: saved.reload.query['payload'] }, headers: agent_a.create_new_auth_token, as: :json

      expect(json['payload']).to be_empty
      expect(json['meta']['all_count']).to eq(0)
    end

    it 'gestor A (acompanhar) lista A e descendentes, sem B nem o controle nativo' do
      post filter_path, params: { payload: status_open }, headers: manager_a.create_new_auth_token, as: :json

      expect(json['payload'].pluck('id')).to contain_exactly(conv_a.display_id, conv_a1.display_id)
      expect(json['meta']['all_count']).to eq(2)
    end

    it 'membro sem grant recebe lista e contagem zeradas' do
      post filter_path, params: { payload: status_open }, headers: member_without_grant.create_new_auth_token, as: :json

      expect(json['payload']).to be_empty
      expect(json['meta']['all_count']).to eq(0)
    end

    it 'admin nominal não recebe conteúdo da inbox marcada pelo filtro' do
      post filter_path, params: { payload: status_open }, headers: admin_nominal.create_new_auth_token, as: :json

      expect(json['payload']).to be_empty
      expect(json['meta']['all_count']).to eq(0)
    end

    it 'filtra antes da paginação também no POST: cada página traz só itens visíveis ao agente' do
      with_modified_env CONVERSATION_RESULTS_PER_PAGE: '1' do
        pages = (1..3).map do |page|
          post filter_path, params: { payload: status_open, page: page }, headers: agent_a.create_new_auth_token, as: :json
          JSON.parse(response.body)['payload'].pluck('id')
        end

        expect(pages.map(&:size)).to eq([1, 1, 1])
        expect(pages.flatten).to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_control.display_id)
      end
    end

    it 'meta e busca usam a mesma relação: B não encontra o texto de A nem conta a conversa de A' do
      get "#{conversations_path}/meta", headers: agent_b.create_new_auth_token
      expect(json['meta']['all_count']).to eq(1)

      get "#{conversations_path}/search", params: { q: 'mensagem de A' }, headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['payload']).to be_empty
    end
  end

  describe 'mensagens (GET e escrita pelos hooks G0)' do
    it 'agente A lê as mensagens da própria conversa' do
      get messages_path, headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('mensagem de A')
    end

    it 'agente B não lê mensagens da conversa de A (404) e o conteúdo não aparece' do
      get messages_path, headers: agent_b.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('mensagem de A')
    end

    it 'gestor A lê mensagens de A, mas não envia (403) e nada é gravado' do
      get messages_path, headers: manager_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      expect do
        post messages_path, params: { content: 'nao', message_type: 'outgoing' }, headers: manager_a.create_new_auth_token
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'gestor A não atualiza nem apaga mensagem (403) e a mensagem fica intacta' do
      patch "#{messages_path}/#{message_a.id}", params: { status: 'failed' }, headers: manager_a.create_new_auth_token
      expect(response).to have_http_status(:forbidden)

      delete "#{messages_path}/#{message_a.id}", headers: manager_a.create_new_auth_token
      expect(response).to have_http_status(:forbidden)

      expect(message_a.reload.status).to eq('sent')
      expect(Message.exists?(message_a.id)).to be(true)
    end

    it 'membro sem grant não lê nem envia mensagem na inbox marcada' do
      get messages_path, headers: member_without_grant.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      expect do
        post messages_path, params: { content: 'nao', message_type: 'outgoing' }, headers: member_without_grant.create_new_auth_token
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'atende a conversa ativa mesmo com outro assignee: o agente com grant opera' do
      conv_a.update!(assignee: agent_b)

      expect do
        post messages_path, params: { content: 'olá', message_type: 'outgoing' }, headers: agent_a.create_new_auth_token
      end.to change(Message, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it 'transferring: leitura permitida, escrita negada (403)' do
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'transferring')

      get messages_path, headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      expect do
        post messages_path, params: { content: 'nao', message_type: 'outgoing' }, headers: agent_a.create_new_auth_token
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'versão de caso inválida (case_version 0): leitura permitida, escrita negada (403)' do
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(case_version: 0)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      post messages_path, params: { content: 'nao', message_type: 'outgoing' }, headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end

    it 'pending_activation e activation_stuck negam leitura e escrita ao agente com grant' do
      [conv_pending, conv_stuck].each do |conversation|
        get "#{conversations_path}/#{conversation.display_id}/messages", headers: agent_a.create_new_auth_token
        expect(response).to have_http_status(:not_found)

        expect do
          post "#{conversations_path}/#{conversation.display_id}/messages", params: { content: 'nao', message_type: 'outgoing' },
                                                                            headers: agent_a.create_new_auth_token
        end.not_to change(Message, :count)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'rascunho, participantes, etiquetas, prioridade, agendamento e transferência' do
    it 'agente A grava e lê o próprio rascunho; B não acessa o rascunho de A' do
      put "#{conversations_path}/#{conv_a.display_id}/draft_messages", params: { draft_message: { message: 'rascunho' } },
                                                                       headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      get "#{conversations_path}/#{conv_a.display_id}/draft_messages", headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'gestor não grava rascunho nem altera participantes da conversa' do
      headers = manager_a.create_new_auth_token
      base = "#{conversations_path}/#{conv_a.display_id}"

      put "#{base}/draft_messages", params: { draft_message: { message: 'x' } }, headers: headers
      expect(response).to have_http_status(:forbidden)

      expect do
        post "#{base}/participants", params: { user_ids: [agent_b.id] }, headers: headers
      end.not_to change(ConversationParticipant, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'gestor não etiqueta, não muda prioridade e não agenda mensagem' do
      headers = manager_a.create_new_auth_token
      base = "#{conversations_path}/#{conv_a.display_id}"

      post "#{base}/labels", params: { labels: ['vip'] }, headers: headers
      expect(response).to have_http_status(:forbidden)

      post "#{base}/toggle_priority", params: { priority: 'high' }, headers: headers
      expect(response).to have_http_status(:forbidden)

      expect do
        post "#{base}/scheduled_messages", params: { content: 'x', scheduled_at: 1.hour.from_now.iso8601 }, headers: headers
      end.not_to change(ScheduledMessage, :count)
      expect(response).to have_http_status(:forbidden)

      expect(conv_a.reload.priority).to be_nil
      expect(conv_a.labels.count).to eq(0)
    end

    it 'agente com grant altera a prioridade da própria conversa' do
      post "#{conversations_path}/#{conv_a.display_id}/toggle_priority", params: { priority: 'high' }, headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.priority).to eq('high')
    end

    it 'transferência legada não é acionada na inbox marcada: negada antes de qualquer chamada ao serviço' do
      expect(Connecta::TransferService).not_to receive(:new)

      post "#{conversations_path}/#{conv_a.display_id}/connecta_transfer", params: { target_department_id: 'x' },
                                                                           headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:forbidden)

      get "#{conversations_path}/#{conv_a.display_id}/connecta_transfer/destinations", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'origem não reabre por rota, status ou campo forjado' do
    it 'conversa transferida não reabre por toggle_status, update ou atribuição do agente com grant' do
      conv_transferred.update!(status: :resolved)
      headers = agent_a.create_new_auth_token
      base = "#{conversations_path}/#{conv_transferred.display_id}"

      post "#{base}/toggle_status", params: { status: 'open' }, headers: headers
      expect(response).to have_http_status(:not_found)

      put base, params: { status: 'open', snoozed_until: nil }, headers: headers
      expect(response).to have_http_status(:not_found)

      post "#{base}/assignments", params: { assignee_id: agent_a.id }, headers: headers
      expect(response).to have_http_status(:not_found)

      expect(conv_transferred.reload.status).to eq('resolved')
      expect(conv_transferred.assignee_id).to be_nil
    end

    it 'transferring: reabrir ou encerrar pelo agente é negado (403) e o status não muda' do
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'transferring')
      conv_a.update!(status: :resolved)

      post "#{conversations_path}/#{conv_a.display_id}/toggle_status", params: { status: 'open' }, headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('resolved')
    end
  end

  describe 'criação de conversa na inbox marcada (admissão única)' do
    it 'agente A não cria conversa na inbox marcada, nem com status forjado (403) e sem gravar nada' do
      expect do
        post conversations_path, params: { inbox_id: whatsapp_inbox.id, contact_id: contact_a.id, status: 'open' },
                                 headers: agent_a.create_new_auth_token
      end.not_to change(Conversation, :count)

      expect(response).to have_http_status(:forbidden)
      expect(Connecta::Scope::AccessAudit.where(user_id: agent_a.id, access_path: 'conversation_create', decision: 'deny').count).to eq(1)
    end

    it 'agente A não reabre a origem informando só o source_id da conversa de A (403)' do
      expect do
        post conversations_path, params: { source_id: conv_a.contact_inbox.source_id }, headers: agent_a.create_new_auth_token
      end.not_to change(Conversation, :count)

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('open')
    end

    it 'admin nominal não cria conversa na inbox marcada (só lê)' do
      expect do
        post conversations_path, params: { inbox_id: whatsapp_inbox.id, contact_id: contact_a.id }, headers: admin_nominal.create_new_auth_token
      end.not_to change(Conversation, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'inbox não marcada segue nativa: agente membro cria conversa' do
      expect do
        post conversations_path, params: { inbox_id: control_inbox.id, contact_id: contact_control.id },
                                 headers: agent_a.create_new_auth_token
      end.to change(Conversation, :count).by(1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'autenticação e auditoria' do
    it 'sem token, lista, detalhe e mensagens respondem 401' do
      get conversations_path
      expect(response).to have_http_status(:unauthorized)

      get "#{conversations_path}/#{conv_a.display_id}"
      expect(response).to have_http_status(:unauthorized)

      get messages_path
      expect(response).to have_http_status(:unauthorized)
    end

    it 'sem token, filtro, envio e criação respondem 401 e nada é gravado' do
      post filter_path, params: { payload: status_open }, as: :json
      expect(response).to have_http_status(:unauthorized)

      expect do
        post messages_path, params: { content: 'anon', message_type: 'outgoing' }
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:unauthorized)

      expect do
        post conversations_path, params: { inbox_id: whatsapp_inbox.id, contact_id: contact_a.id }
      end.not_to change(Conversation, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'admin nominal lê mensagens de A e a leitura fica auditada por conversa' do
      get messages_path, headers: admin_nominal.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('mensagem de A')
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_a.id, access_path: 'detail',
                                                decision: 'allow').count).to be >= 1
    end

    it 'admin nominal não escreve na conversa e a tentativa fica negada na auditoria' do
      post "#{conversations_path}/#{conv_a.display_id}/toggle_status", params: { status: 'resolved' },
                                                                       headers: admin_nominal.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('open')
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_a.id,
                                                access_path: 'conversation_toggle_status', decision: 'deny').count).to eq(1)
    end
  end
end
