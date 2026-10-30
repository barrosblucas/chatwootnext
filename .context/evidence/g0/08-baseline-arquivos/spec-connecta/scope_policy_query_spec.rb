require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 parte A (spike G0): dois setores (A e B) na MESMA inbox WhatsApp. Policy, query e HTTP são os reais;
# nenhuma decisão de autorização ou resultado de consulta é mockado. Inbox nativa sem marca serve só de controle.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · escopo de conversas (T0.2 parte A)', type: :request do
  include_context 'with connecta g0 scope fixture'

  describe 'lista (GET conversations)' do
    it 'agente A vê o próprio setor, o descendente e o controle nativo, com contagem coerente' do
      get conversations_path, headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_control.display_id)
      expect(json['data']['meta']['all_count']).to eq(3)
    end

    it 'agente B vê só o setor B, sem a conversa de A na mesma inbox' do
      get conversations_path, headers: agent_b.create_new_auth_token

      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_b.display_id)
      expect(json['data']['meta']['all_count']).to eq(1)
    end

    it 'gestor A (acompanhar) vê A e descendentes, mas não B nem o controle nativo' do
      get conversations_path, headers: manager_a.create_new_auth_token

      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_a.display_id, conv_a1.display_id)
      expect(json['data']['meta']['all_count']).to eq(2)
    end

    it 'membro da inbox sem grant não vê nenhuma conversa da inbox marcada' do
      get conversations_path, headers: member_without_grant.create_new_auth_token

      expect(json['data']['payload']).to be_empty
      expect(json['data']['meta']['all_count']).to eq(0)
    end

    it 'admin nominal não recebe conteúdo da inbox marcada na listagem; a listagem fica auditada como metadado' do
      get conversations_path, headers: admin_nominal.create_new_auth_token

      expect(json['data']['payload']).to be_empty
      expect(json['data']['meta']['all_count']).to eq(0)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, access_path: 'list', decision: 'allow').count).to eq(1)
    end

    it 'filtra antes da paginação: com 1 item por página, as páginas trazem só o que o agente pode ver' do
      with_modified_env CONVERSATION_RESULTS_PER_PAGE: '1' do
        pages = (1..3).map do |page|
          get conversations_path, params: { page: page }, headers: agent_a.create_new_auth_token
          JSON.parse(response.body).dig('data', 'payload').pluck('id')
        end

        expect(pages.map(&:size)).to eq([1, 1, 1])
        expect(pages.flatten).to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_control.display_id)
      end
    end

    it 'ignora ator e setor forjados: agente B não ganha A por parâmetro ou cabeçalho' do
      get conversations_path,
          params: { actor_id: agent_a.id, org_unit_id: org_a.id, sector: 'A', user_id: agent_a.id },
          headers: agent_b.create_new_auth_token.merge('X-Connecta-Actor' => agent_a.id.to_s, 'X-Connecta-Org-Unit' => 'A')

      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_b.display_id)
      expect(json['data']['meta']['all_count']).to eq(1)
    end
  end

  describe 'detalhe por URL (GET conversations/:id)' do
    it 'agente A lê a própria conversa' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json['id']).to eq(conv_a.display_id)
    end

    it 'agente B não abre a conversa de A, mesmo na mesma inbox (404: a conversa não é revelada)' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_b.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'gestor A lê descendente de A, mas não o conteúdo de B' do
      get "#{conversations_path}/#{conv_a1.display_id}", headers: manager_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      get "#{conversations_path}/#{conv_b.display_id}", headers: manager_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'membro sem grant não abre nenhuma conversa da inbox marcada' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: member_without_grant.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'admin nominal lê conversa transferida e a leitura fica auditada' do
      get "#{conversations_path}/#{conv_transferred.display_id}", headers: admin_nominal.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_transferred.id,
                                                access_path: 'detail', decision: 'allow').count).to eq(1)
    end

    it 'controle nativo: inbox não marcada segue a regra nativa (membro lê, não membro não lê)' do
      get "#{conversations_path}/#{conv_control.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      get "#{conversations_path}/#{conv_control.display_id}", headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'política real (ConversationPolicy#show?) sem mock' do
    def policy_for(user)
      ConversationPolicy.new({ user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }, conv_a)
    end

    it 'decide por grant e escopo, não por papel de agente nativo' do
      expect(policy_for(agent_a).show?).to be(true)
      expect(policy_for(manager_a).show?).to be(true)
      expect(policy_for(agent_b).show?).to be(false)
      expect(policy_for(member_without_grant).show?).to be(false)
    end
  end

  describe 'estados e fail-closed' do
    it 'escopo ausente na inbox marcada só é lido pelo admin nominal' do
      get "#{conversations_path}/#{conv_orphan.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get "#{conversations_path}/#{conv_orphan.display_id}", headers: admin_nominal.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it 'estado transferred_out não dá acesso ao agente com grant' do
      get "#{conversations_path}/#{conv_transferred.display_id}", headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'transferring permite leitura, mas bloqueia envio de mensagem' do
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'transferring')

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'bloqueado', message_type: 'outgoing' },
                                                                    headers: agent_a.create_new_auth_token
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'inbox em admin_only nega agentes e mantém o admin nominal' do
      marked_inbox.update!(enforcement: 'admin_only')

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get "#{conversations_path}/#{conv_a.display_id}", headers: admin_nominal.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it 'manutenção da inbox nega não-admin (a inbox não marcada do agente continua nativa)' do
      marked_inbox.update!(maintenance: true)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'heartbeat vencido nega não-admin na lista e no detalhe' do
      projection_heartbeat.update!(last_heartbeat_at: 10.minutes.ago)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get "#{conversations_path}/#{conv_transferred.display_id}", headers: admin_nominal.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it 'revogação local vale na requisição seguinte, sem cache' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(revoked_locally_at: Time.current)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)
    end
  end

  describe 'escrita (gestor sem escrita; agente com grant escreve)' do
    it 'agente A envia mensagem na própria conversa' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'olá', message_type: 'outgoing' },
                                                                    headers: agent_a.create_new_auth_token
      end.to change(Message, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it 'gestor A não envia mensagem e a tentativa fica negada na auditoria' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'nao', message_type: 'outgoing' },
                                                                    headers: manager_a.create_new_auth_token
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:forbidden)
      expect(Connecta::Scope::AccessAudit.where(user_id: manager_a.id, access_path: 'message_create', decision: 'deny').count).to eq(1)
    end

    it 'agente B não envia mensagem na conversa de A (404: a conversa não é revelada)' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'nao', message_type: 'outgoing' },
                                                                    headers: agent_b.create_new_auth_token
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'gestor A não encerra a conversa' do
      post "#{conversations_path}/#{conv_a.display_id}/toggle_status", params: { status: 'resolved' },
                                                                       headers: manager_a.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('open')
    end

    it 'agente A encerra a própria conversa na etapa ativa' do
      post "#{conversations_path}/#{conv_a.display_id}/toggle_status", params: { status: 'resolved' },
                                                                       headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.status).to eq('resolved')
    end

    it 'gestor A não atribui a conversa a outro agente' do
      post "#{conversations_path}/#{conv_a.display_id}/assignments", params: { assignee_id: agent_a.id },
                                                                     headers: manager_a.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.assignee_id).to be_nil
    end

    it 'controle nativo: agente membro segue enviando mensagem na inbox não marcada' do
      expect do
        post "#{conversations_path}/#{conv_control.display_id}/messages",
             params: { content: 'controle', message_type: 'outgoing' },
             headers: agent_a.create_new_auth_token
      end.to change(Message, :count).by(1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'esquema do protótipo' do
    it 'índices: um escopo por conversa; um escopo não terminal por contato na inbox; estado terminal libera o contato' do
      # Savepoint: a violação do índice não pode abortar a transação do exemplo.
      expect do
        Connecta::Scope::ConversationScope.transaction(requires_new: true) do
          Connecta::Scope::ConversationScope.create!(conversation_id: conv_orphan.id, inbox_id: whatsapp_inbox.id,
                                                     contact_id: contact_a.id, org_unit: org_a, state: 'reception')
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)

      expect do
        Connecta::Scope::ConversationScope.transaction(requires_new: true) do
          Connecta::Scope::ConversationScope.create!(conversation_id: conv_a.id, inbox_id: whatsapp_inbox.id,
                                                     contact_id: contact_b.id, org_unit: org_a, state: 'reception')
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)

      Connecta::Scope::ConversationScope.create!(conversation_id: conv_orphan.id, inbox_id: whatsapp_inbox.id,
                                                 contact_id: contact_a.id, org_unit: org_a, state: 'transferred_out')
      expect(Connecta::Scope::ConversationScope.where(contact_id: contact_a.id).count).to eq(2)
    end

    it 'registro de auditoria é append-only' do
      audit = Connecta::Scope::AccessAudit.create!(user_id: agent_a.id, conversation_id: conv_a.id, surface: 'conversation',
                                                   access_path: 'detail', decision: 'allow', created_at: Time.current)

      expect { audit.update!(decision: 'deny') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
