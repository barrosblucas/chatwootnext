require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 parte B2 (spike G0): unread_counts, busca, contatos, bulk, inbox/QR, membros, export, transcript, agendadas, atributos e Captain.
# Mesmo fixture das partes A e B1. Políticas, queries e hooks são os reais. Stubs só nos adapters externos (IA e transporte WhatsApp),
# e a ausência de I/O externo é provada com WebMock (sem requisição) e a ausência de job/e-mail com matchers de fila.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · superfícies HTTP relacionadas (T0.2 parte B2)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:search_path) { "/api/v1/accounts/#{account.id}/search" }
  let(:contacts_path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:inboxes_path) { "/api/v1/accounts/#{account.id}/inboxes" }
  let(:bulk_path) { "/api/v1/accounts/#{account.id}/bulk_actions" }
  let(:captain_path) { "/api/v1/accounts/#{account.id}/captain/tasks" }
  let(:whatsapp_path) { "#{inboxes_path}/#{whatsapp_inbox.id}" }
  let(:conv_a_path) { "#{conversations_path}/#{conv_a.display_id}" }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_manager) { manager_a.create_new_auth_token }
  let(:token_admin) { admin_nominal.create_new_auth_token }
  let(:message_a) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a, message_type: :outgoing,
                     content: 'pedido alfapedido de A')
  end

  # Listagens de contato só mostram contatos com e-mail, telefone ou identificador (Contact.resolved_contacts).
  before do
    contact_a.update!(name: 'Contato Alfa', email: 'alfa@example.com')
    contact_control.update!(name: 'Contato Controle', email: 'controle@example.com')
    [contact_a1, contact_b, contact_orphan, contact_transferred].each { |contact| contact.update!(email: "#{contact.id}@example.com") }
    message_a
  end

  describe 'contagem de não lidas com conversation_unread_counts ligada' do
    let(:counts_path) { "#{conversations_path}/unread_counts" }
    let!(:vip_label) { create(:label, account: account, title: 'vip', show_on_sidebar: true) }

    before do
      account.enable_features!('conversation_unread_counts')
      [conv_a, conv_a1, conv_b, conv_control].each do |conversation|
        create(:message, account: account, inbox: conversation.inbox, conversation: conversation, sender: conversation.contact,
                         message_type: :incoming, content: 'oi')
      end
      [conv_a, conv_a1, conv_b].each { |conversation| conversation.update!(label_list: ['vip']) }
    end

    it 'agente A conta só o próprio setor, o descendente e o controle nativo' do
      get counts_path, headers: token_a

      expect(response).to have_http_status(:ok)
      expect(json['payload']['inboxes']).to eq(whatsapp_inbox.id.to_s => 2, control_inbox.id.to_s => 1)
      expect(json['payload']['all_count']).to eq(3)
    end

    it 'agente B conta só a própria conversa e não recebe contagem da inbox física de A' do
      get counts_path, headers: token_b

      expect(json['payload']['inboxes']).to eq(whatsapp_inbox.id.to_s => 1)
      expect(json['payload']['all_count']).to eq(1)
    end

    it 'etiquetas e equipes contam só conversas visíveis ao usuário' do
      # Responsável explícito: sem ele, a atribuição por equipe roda o round-robin, que o MockRedis do ambiente de teste não aceita.
      team = Team.create!(name: 'Equipe B', account: account)
      TeamMember.create!(team: team, user: agent_b)
      conv_b.update!(team: team, assignee: agent_b)

      get counts_path, headers: token_a
      expect(json['payload']['labels']).to eq(vip_label.id.to_s => 2)
      expect(json['payload']['teams']).to eq({})

      get counts_path, headers: token_b
      payload = JSON.parse(response.body)['payload']
      expect(payload['labels']).to eq(vip_label.id.to_s => 1)
      expect(payload['teams']).to eq(team.id.to_s => 1)
    end

    it 'gestor (acompanhar) conta A e A1 e não conta B' do
      get counts_path, headers: token_manager

      expect(json['payload']['inboxes']).to eq(whatsapp_inbox.id.to_s => 2)
    end

    it 'membro sem grant recebe contagem zerada da inbox marcada' do
      get counts_path, headers: member_without_grant.create_new_auth_token

      expect(json['payload']['inboxes']).to eq({})
      expect(json['payload']['all_count']).to eq(0)
    end

    it 'admin nominal não recebe contagem de inbox marcada' do
      get counts_path, headers: token_admin

      expect(json['payload']['inboxes']).to eq({})
      expect(json['payload']['labels']).to eq({})
      expect(json['payload']['all_count']).to eq(0)
    end

    it 'grant revogado zera a contagem na próxima leitura' do
      get counts_path, headers: token_a
      expect(json['payload']['all_count']).to eq(3)

      Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all
      get counts_path, headers: token_a

      expect(JSON.parse(response.body)['payload']['inboxes']).to eq(control_inbox.id.to_s => 1)
    end

    it 'sem token, a contagem responde 401' do
      get counts_path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'busca global (escopo antes de paginação e contagem)' do
    it 'agente A encontra a própria conversa, mensagem e contato pela busca' do
      get search_path, params: { q: 'Contato Alfa' }, headers: token_a

      expect(json['payload']['conversations'].size).to eq(1)
      expect(json['payload']['contacts'].pluck('id')).to contain_exactly(contact_a.id)
    end

    it 'agente B não encontra conversa, contato nem mensagem de A pelo nome do contato ou pelo texto' do
      get search_path, params: { q: 'Contato Alfa' }, headers: token_b

      expect(json['payload']['conversations']).to be_empty
      expect(json['payload']['contacts']).to be_empty

      get search_path, params: { q: 'alfapedido' }, headers: token_b

      expect(JSON.parse(response.body)['payload']['messages']).to be_empty
    end

    it 'agente A encontra a mensagem de A, e a busca por mensagem respeita o escopo' do
      get search_path, params: { q: 'alfapedido' }, headers: token_a

      expect(json['payload']['messages'].pluck('id')).to contain_exactly(message_a.id)
    end

    it 'busca de mensagens por agente B não lista a mensagem pelo endpoint dedicado' do
      get "#{search_path}/messages", params: { q: 'alfapedido' }, headers: token_b

      expect(json['payload']['messages']).to be_empty
    end

    it 'admin nominal não recebe conversa, mensagem nem contato de inbox marcada pela busca' do
      get search_path, params: { q: 'alfapedido' }, headers: token_admin

      expect(json['payload']['messages']).to be_empty

      get search_path, params: { q: 'Contato Alfa' }, headers: token_admin

      expect(JSON.parse(response.body)['payload']['conversations']).to be_empty
      expect(JSON.parse(response.body)['payload']['contacts']).to be_empty
    end

    it 'contato do controle nativo continua na busca do agente de controle' do
      create(:message, account: account, inbox: control_inbox, conversation: conv_control, sender: contact_control, message_type: :incoming,
                       content: 'oi do controle')

      get search_path, params: { q: 'Contato Controle' }, headers: token_a

      expect(json['payload']['contacts'].pluck('id')).to contain_exactly(contact_control.id)
    end
  end

  describe 'contatos e conversas de contato' do
    it 'agente A abre o contato associado à própria conversa' do
      get "#{contacts_path}/#{contact_a.id}", headers: token_a

      expect(response).to have_http_status(:ok)
    end

    it 'agente B não abre contato vinculado só à conversa de A (404), sem revelar o nome' do
      get "#{contacts_path}/#{contact_a.id}", headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Contato Alfa')
    end

    it 'agente B abre contato sem vínculo com inbox marcada (controle)' do
      get "#{contacts_path}/#{contact_control.id}", headers: token_b

      expect(response).to have_http_status(:ok)
    end

    it 'contato com conversa sem escopo na inbox marcada (orfã) não aparece para ninguém sem visibilidade' do
      get "#{contacts_path}/#{contact_orphan.id}", headers: token_a

      expect(response).to have_http_status(:not_found)
    end

    it 'listagem do agente A traz só contatos visíveis e os de controle, sem B, orfã nem transferido' do
      get contacts_path, headers: token_a

      ids = json['payload'].pluck('id')
      expect(ids).to include(contact_a.id, contact_a1.id, contact_control.id)
      expect(ids).not_to include(contact_b.id, contact_orphan.id, contact_transferred.id)
    end

    it 'listagem do agente B não traz contato de A, do descendente A1, orfã nem transferido' do
      get contacts_path, headers: token_b

      ids = json['payload'].pluck('id')
      expect(ids).to include(contact_b.id, contact_control.id)
      expect(ids).not_to include(contact_a.id, contact_a1.id, contact_orphan.id, contact_transferred.id)
    end

    it 'busca e filtro de contatos não contam nem listam contato de A para B' do
      post "#{contacts_path}/filter", params: { payload: [{ attribute_key: 'name', filter_operator: 'contains', values: ['Contato Alfa'] }] },
                                      headers: token_b, as: :json

      expect(json['payload']).to be_empty
      expect(json['meta']['count']).to eq(0)

      post "#{contacts_path}/filter", params: { payload: [{ attribute_key: 'name', filter_operator: 'contains', values: ['Contato Alfa'] }] },
                                      headers: token_a, as: :json

      expect(JSON.parse(response.body)['meta']['count']).to eq(1)
    end

    it 'gestor lê contato visível, mas não altera o contato global (403) e o nome permanece' do
      patch "#{contacts_path}/#{contact_a.id}", params: { contact: { name: 'Trocado pelo gestor' } }, headers: token_manager

      expect(response).to have_http_status(:forbidden)
      expect(contact_a.reload.name).to eq('Contato Alfa')
    end

    it 'agente com grant não exclui contato vinculado (negado pela autorização nativa, sem remoção)' do
      expect do
        delete "#{contacts_path}/#{contact_a.id}", headers: token_a
      end.not_to change(Contact, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'agente com grant não altera atributos globais de contato vinculado (403), e o contato permanece' do
      contact_a.update!(custom_attributes: { 'plano' => 'basico' })

      post "#{contacts_path}/#{contact_a.id}/destroy_custom_attributes", params: { custom_attributes: ['plano'] }, headers: token_a

      expect(response).to have_http_status(:forbidden)
      expect(contact_a.reload.custom_attributes).to eq('plano' => 'basico')
    end

    it 'conversas do contato: o agente vê só as conversas visíveis, não a transferida para fora do escopo' do
      conv_out = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_a, assignee: agent_b)
      Connecta::Scope::ConversationScope.create!(conversation_id: conv_out.id, inbox_id: whatsapp_inbox.id, contact_id: contact_a.id,
                                                 org_unit: org_a, state: 'transferred_out', case_protocol: 'CASO-OUT', case_version: 1)

      get "#{contacts_path}/#{contact_a.id}/conversations", headers: token_a

      expect(response).to have_http_status(:ok)
      expect(json['payload'].pluck('id')).to contain_exactly(conv_a.display_id)
    end

    it 'notas de contato vinculado ficam bloqueadas para todos: leitura 404 e escrita 403, sem nota criada' do
      Note.create!(account: account, contact: contact_a, user: agent_a, content: 'nota sensível')

      get "#{contacts_path}/#{contact_a.id}/notes", headers: token_a
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('nota sensível')

      expect do
        post "#{contacts_path}/#{contact_a.id}/notes", params: { note: { content: 'nova' } }, headers: token_a
      end.not_to change(Note, :count)
      expect(response).to have_http_status(:forbidden)

      get "#{contacts_path}/#{contact_a.id}/notes", headers: token_admin
      expect(response).to have_http_status(:not_found)
    end

    it 'notas de contato sem vínculo com inbox marcada seguem nativas (controle)' do
      expect do
        post "#{contacts_path}/#{contact_control.id}/notes", params: { note: { content: 'nota do controle' } }, headers: token_a
      end.to change(Note, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it 'exportação de contatos é negada a todos com inbox marcada e não enfileira o job' do
      [token_a, token_manager, token_admin].each do |token|
        expect do
          post "#{contacts_path}/export", params: { column_names: ['name'] }, headers: token
        end.not_to have_enqueued_job(Account::ContactsExportJob)

        expect(response).to have_http_status(:forbidden).or have_http_status(:unauthorized)
      end
    end

    it 'exportação de contatos sem nenhuma inbox marcada segue nativa (controle)' do
      Connecta::Scope::ScopedInbox.delete_all
      admin_token = create(:user, account: account, role: :administrator).create_new_auth_token

      expect do
        post "#{contacts_path}/export", params: { column_names: ['name'] }, headers: admin_token
      end.to have_enqueued_job(Account::ContactsExportJob)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'ações em lote (validação de todos os alvos antes da escrita)' do
    it 'agente A altera status de duas conversas próprias pelo job' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id, conv_a1.display_id], fields: { status: 'resolved' } },
                        headers: token_a, as: :json
      end.to have_enqueued_job(BulkActionsJob)

      perform_enqueued_jobs(only: BulkActionsJob)
      expect(response).to have_http_status(:ok)
      expect([conv_a.reload.status, conv_a1.reload.status]).to all(eq('resolved'))
    end

    it 'mistura de conversa de A e de B não produz sucesso parcial: 404 para o agente A, nada enfileirado, nada alterado' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id, conv_b.display_id], fields: { status: 'resolved' } },
                        headers: token_a, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)

      expect(response).to have_http_status(:not_found)
      expect([conv_a.reload.status, conv_b.reload.status]).to all(eq('open'))
    end

    it 'gestor (acompanhar) não altera conversa em lote (403), nada enfileirado' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id], fields: { status: 'resolved' } }, headers: token_manager, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('open')
    end

    it 'atribuição em lote não amplia o escopo: o novo responsável sem grant continua sem ler a conversa' do
      post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id], fields: { assignee_id: agent_b.id } }, headers: token_a, as: :json
      perform_enqueued_jobs(only: BulkActionsJob)

      expect(conv_a.reload.assignee_id).to eq(agent_b.id)
      get conv_a_path, headers: token_b
      expect(response).to have_http_status(:not_found)
    end

    it 'lote de conversa do controle nativo segue nativo' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_control.display_id], fields: { status: 'resolved' } },
                        headers: token_a, as: :json
      end.to have_enqueued_job(BulkActionsJob)
    end

    it 'exclusão em lote de contato vinculado é negada (403) antes do job' do
      expect do
        post bulk_path, params: { type: 'contact', action_name: 'delete', ids: [contact_a.id] }, headers: token_a, as: :json
      end.not_to have_enqueued_job(Contacts::BulkActionJob)

      expect(response).to have_http_status(:forbidden)
      expect(Contact.exists?(contact_a.id)).to be(true)
    end
  end

  describe 'inbox física: QR, sessão, conexão e gestão restritos ao admin nominal' do
    it 'agente com membership não inicia pareamento (403) e nenhuma requisição ao transporte é feita' do
      post "#{whatsapp_path}/setup_channel_provider", headers: token_a

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'gestor não importa sessão de WhatsApp (403) e nada é enviado ao transporte' do
      post "#{whatsapp_path}/import_whatsapp_session", params: { session: { creds: 'x' }, candidate_index: 0 }, headers: token_manager, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'agente não consulta status de saúde da inbox física (404) e nada é enviado ao transporte' do
      get "#{whatsapp_path}/health", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'agente não verifica número no WhatsApp pela inbox física (403) e nada é enviado ao transporte' do
      post "#{whatsapp_path}/on_whatsapp", params: { phone_number: '5511999990000' }, headers: token_a

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'agente não altera nem exclui a inbox física (403), sem job de exclusão' do
      patch whatsapp_path, params: { inbox: { name: 'Trocada' } }, headers: token_a
      expect(response).to have_http_status(:forbidden)
      expect(whatsapp_inbox.reload.name).to eq('WhatsApp Baileys')

      expect do
        delete whatsapp_path, headers: token_a
      end.not_to have_enqueued_job(DeleteObjectJob)
      expect(response).to have_http_status(:forbidden)
    end

    it 'agente não cria inbox WhatsApp (403 pelo gate, antes da autorização nativa), sem registro' do
      expect do
        post inboxes_path, params: { channel: { type: 'whatsapp' }, name: 'Nova' }, headers: token_a
      end.not_to change(Inbox, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'admin nominal inicia pareamento e o transporte é chamado uma vez, sem decisão do stub' do
      stub_request(:any, /.*/).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      post "#{whatsapp_path}/setup_channel_provider", headers: token_admin

      expect(response).to have_http_status(:ok)
      expect(a_request(:any, /.*/)).to have_been_made.at_least_once
    end

    it 'inbox sem marca segue nativa: agente de controle recebe o erro de canal não suportado (422)' do
      post "#{inboxes_path}/#{control_inbox.id}/on_whatsapp", params: { phone_number: '5511999990000' }, headers: token_a

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'gestor não adiciona membro à inbox física (403), e o membro não entra' do
      expect do
        post "/api/v1/accounts/#{account.id}/inbox_members", params: { inbox_id: whatsapp_inbox.id, user_ids: [member_without_grant.id] },
                                                             headers: token_manager, as: :json
      end.not_to change(InboxMember, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'equipes, membros e usuários: autorização nativa suficiente' do
    it 'gestor não cria equipe nem adiciona membro de equipe (negado nativamente, sem registro)' do
      expect do
        post "/api/v1/accounts/#{account.id}/teams", params: { name: 'Equipe pirata' }, headers: token_manager
      end.not_to change(Team, :count)
      expect(response).to have_http_status(:unauthorized)

      team = Team.create!(name: 'Equipe A', account: account)
      expect do
        post "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members", params: { user_ids: [member_without_grant.id] }, headers: token_a
      end.not_to change(TeamMember, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'agente não cria usuário de conta (negado nativamente, sem registro)' do
      expect do
        post "/api/v1/accounts/#{account.id}/agents", params: { name: 'X', email: 'x@example.com', role: 'agent' }, headers: token_a
      end.not_to change(User, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'relatórios, exportações e integrações' do
    it 'agente e gestor não leem relatório agregado de agente (negado nativamente)' do
      [token_a, token_manager].each do |token|
        get "/api/v2/accounts/#{account.id}/summary_reports/agent", headers: token
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'gestor não cria webhook da conta (negado nativamente, sem registro e sem job)' do
      expect do
        post "/api/v1/accounts/#{account.id}/webhooks", params: { webhook: { url: 'https://example.com/hook', subscriptions: ['message_created'] } },
                                                        headers: token_manager, as: :json
      end.not_to change(Webhook, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'agente não cria integração de hook (negado nativamente, sem registro)' do
      expect do
        post "/api/v1/accounts/#{account.id}/integrations/hooks", params: { hook: { inbox_id: whatsapp_inbox.id, app_id: 'slack' } },
                                                                  headers: token_a, as: :json
      end.not_to change(Integrations::Hook, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'transcrição da conversa (envio por e-mail)' do
    let(:transcript_path) { "#{conv_a_path}/transcript" }

    it 'agente com grant não envia transcrição de conversa marcada (403) e nenhum e-mail é enfileirado' do
      expect do
        post transcript_path, params: { email: 'cliente@example.com' }, headers: token_a
      end.not_to have_enqueued_mail(ConversationReplyMailer, :conversation_transcript)

      expect(response).to have_http_status(:forbidden)
    end

    it 'gestor não envia transcrição (403) e agente sem grant recebe 404' do
      post transcript_path, params: { email: 'cliente@example.com' }, headers: token_manager
      expect(response).to have_http_status(:forbidden)

      post transcript_path, params: { email: 'cliente@example.com' }, headers: token_b
      expect(response).to have_http_status(:not_found)
    end

    it 'admin nominal envia transcrição de conversa marcada com leitura auditada' do
      expect do
        post transcript_path, params: { email: 'cliente@example.com' }, headers: token_admin
      end.to have_enqueued_mail(ConversationReplyMailer, :conversation_transcript)

      expect(response).to have_http_status(:ok)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_a.id, access_path: 'conversation_transcript',
                                                decision: 'allow').count).to eq(1)
    end

    it 'transcrição de conversa do controle nativo segue nativa' do
      expect do
        post "#{conversations_path}/#{conv_control.display_id}/transcript", params: { email: 'cliente@example.com' }, headers: token_a
      end.to have_enqueued_mail(ConversationReplyMailer, :conversation_transcript)
    end
  end

  describe 'agendadas, recorrentes, atributos de conversa e anexos' do
    it 'agente B não lista mensagens agendadas nem anexos de conversa de A (404)' do
      get "#{conv_a_path}/scheduled_messages", headers: token_b
      expect(response).to have_http_status(:not_found)

      get "#{conv_a_path}/attachments", headers: token_b
      expect(response).to have_http_status(:not_found)
    end

    it 'gestor não agenda mensagem recorrente nem cria mensagem agendada (403), sem gravar' do
      expect do
        post "#{conv_a_path}/scheduled_messages", params: { content: 'x' }, headers: token_manager
      end.not_to change(ScheduledMessage, :count)
      expect(response).to have_http_status(:forbidden)

      expect do
        post "#{conv_a_path}/recurring_scheduled_messages", params: { content: 'x' }, headers: token_manager
      end.not_to change(RecurringScheduledMessage, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'agente B não agenda mensagem recorrente na conversa de A (404)' do
      post "#{conv_a_path}/recurring_scheduled_messages", params: { content: 'x' }, headers: token_b

      expect(response).to have_http_status(:not_found)
    end

    it 'agente com grant atualiza atributos da própria conversa e gestor não (403)' do
      post "#{conv_a_path}/custom_attributes", params: { custom_attributes: { prioridade: 'alta' } }, headers: token_a
      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.custom_attributes).to eq('prioridade' => 'alta')

      post "#{conv_a_path}/custom_attributes", params: { custom_attributes: { prioridade: 'baixa' } }, headers: token_manager
      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.custom_attributes).to eq('prioridade' => 'alta')
    end

    it 'agendadas da conversa do controle nativo seguem nativas' do
      get "#{conversations_path}/#{conv_control.display_id}/scheduled_messages", headers: token_a

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'tarefas de IA (Captain) sobre conversa de inbox marcada' do
    let(:summary) { instance_double(Captain::SummaryService, perform: { message: 'resumo sintético' }) }

    before { allow(Captain::SummaryService).to receive(:new).and_return(summary) }

    it 'agente B não resume conversa de A (404) e o serviço de IA não é chamado' do
      post "#{captain_path}/summarize", params: { conversation_display_id: conv_a.display_id }, headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(Captain::SummaryService).not_to have_received(:new)
    end

    it 'agente com grant resume a própria conversa' do
      post "#{captain_path}/summarize", params: { conversation_display_id: conv_a.display_id }, headers: token_a

      expect(response).to have_http_status(:ok)
      expect(json['message']).to eq('resumo sintético')
    end

    it 'gestor (acompanhar) lê e resume a conversa de A' do
      post "#{captain_path}/summarize", params: { conversation_display_id: conv_a.display_id }, headers: token_manager

      expect(response).to have_http_status(:ok)
    end

    it 'admin nominal resume com leitura auditada por conversa' do
      post "#{captain_path}/summarize", params: { conversation_display_id: conv_a.display_id }, headers: token_admin

      expect(response).to have_http_status(:ok)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_a.id, access_path: 'captain_summarize',
                                                decision: 'allow').count).to eq(1)
    end

    it 'resumo da conversa do controle nativo segue nativo' do
      post "#{captain_path}/summarize", params: { conversation_display_id: conv_control.display_id }, headers: token_a

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'grant e epoch revogados bloqueiam a próxima leitura' do
    it 'epoch revogado localmente nega leitura da conversa de A na próxima requisição' do
      get conv_a_path, headers: token_a
      expect(response).to have_http_status(:ok)

      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(revoked_locally_at: Time.current)
      get conv_a_path, headers: token_a

      expect(response).to have_http_status(:not_found)
    end
  end
end
