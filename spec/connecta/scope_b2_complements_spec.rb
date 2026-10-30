require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 complementos da B2 (spike G0): lacunas de 08-recuperacao-b2.md (seção 3) que pedem só exemplos.
# Mesmo fixture das partes A, B1 e B2. Políticas, queries e hooks são os reais. Nenhum adapter externo é chamado.
# Exemplos com prefixo ACHADO documentam um comportamento encontrado e não corrigido aqui.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · complementos da B2 (T0.2)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:contacts_path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:bulk_path) { "/api/v1/accounts/#{account.id}/bulk_actions" }
  let(:inboxes_path) { "/api/v1/accounts/#{account.id}/inboxes" }
  let(:inbox_members_path) { "/api/v1/accounts/#{account.id}/inbox_members" }
  let(:webhooks_path) { "/api/v1/accounts/#{account.id}/webhooks" }
  let(:summary_path) { "/api/v2/accounts/#{account.id}/summary_reports/agent" }
  let(:whatsapp_path) { "#{inboxes_path}/#{whatsapp_inbox.id}" }
  let(:conv_a_path) { "#{conversations_path}/#{conv_a.display_id}" }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_member) { member_without_grant.create_new_auth_token }
  let(:token_admin) { admin_nominal.create_new_auth_token }

  describe 'contatos: criação e atributos customizados' do
    it 'criação por agente A, agente B e membro sem grant responde 200, não devolve conversa e não lê conversa escopada' do
      [token_a, token_b, token_member].each_with_index do |token, index|
        expect do
          post contacts_path, params: { name: "Criado #{index}", email: "criado-#{index}@example.com" }, headers: token
        end.to change(Contact, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('"display_id"')
      end

      expect(Connecta::Scope::AccessAudit.where(surface: 'conversation').count).to eq(0)
    end

    it 'atributos de contato vinculado: A recebe 403, B e membro sem grant recebem 404, e o valor não muda' do
      contact_a.update!(custom_attributes: { 'plano' => 'basico' })

      patch "#{contacts_path}/#{contact_a.id}", params: { custom_attributes: { plano: 'premium' } }, headers: token_a
      expect(response).to have_http_status(:forbidden)

      [token_b, token_member].each do |token|
        patch "#{contacts_path}/#{contact_a.id}", params: { custom_attributes: { plano: 'premium' } }, headers: token
        expect(response).to have_http_status(:not_found)
      end

      expect(contact_a.reload.custom_attributes).to eq('plano' => 'basico')
    end
  end

  describe 'ações em lote de etiqueta (escopo antes do job)' do
    it 'agente A adiciona etiqueta às próprias conversas pelo job' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id, conv_a1.display_id], labels: { add: ['vip'] } },
                        headers: token_a, as: :json
      end.to have_enqueued_job(BulkActionsJob)

      perform_enqueued_jobs(only: BulkActionsJob)
      expect(response).to have_http_status(:ok)
      expect([conv_a.reload.label_list, conv_a1.reload.label_list]).to all(include('vip'))
    end

    it 'mistura de conversa de A e de B com etiqueta, pedida por B: 404, nada enfileirado e nenhuma etiqueta aplicada' do
      expect do
        post bulk_path, params: { type: 'conversation', ids: [conv_a.display_id, conv_b.display_id], labels: { add: ['vip'] } },
                        headers: token_b, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)

      expect(response).to have_http_status(:not_found)
      expect([conv_a.reload.label_list, conv_b.reload.label_list]).to all(be_empty)
    end
  end

  describe 'admin nominal na inbox marcada e em integrações e relatórios' do
    let(:owner_nominal) { create(:user, account: account, role: :administrator) }
    let(:token_owner) { owner_nominal.create_new_auth_token }

    # Administrador da conta com grant admin_nominal: o único caso que passa a autorização nativa de inbox (update), webhook e relatório.
    before do
      create(:inbox_member, inbox: whatsapp_inbox, user: owner_nominal)
      Connecta::Scope::UserAuthEpoch.create!(user_id: owner_nominal.id, epoch: 1)
      Connecta::Scope::UserGrant.create!(user_id: owner_nominal.id, org_unit: org_root, permission: 'admin_nominal')
    end

    it 'admin nominal lê a inbox marcada (200) sem segredo do canal, e essa leitura não gera registro de auditoria' do
      get whatsapp_path, headers: token_admin

      expect(response).to have_http_status(:ok)
      expect(json).not_to have_key('provider_config')
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, surface: 'inbox').count).to eq(0)
    end

    it 'admin nominal lista os membros da inbox marcada (200), sem registro de auditoria' do
      get "#{inbox_members_path}/#{whatsapp_inbox.id}", headers: token_admin

      expect(response).to have_http_status(:ok)
      expect(json['payload'].pluck('id')).to include(agent_a.id, member_without_grant.id)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, surface: 'inbox').count).to eq(0)
    end

    it 'administrador da conta com grant renomeia a inbox marcada (200), com registro allow em inbox_update' do
      patch whatsapp_path, params: { name: 'Renomeada pelo admin' }, headers: token_owner

      expect(response).to have_http_status(:ok)
      expect(whatsapp_inbox.reload.name).to eq('Renomeada pelo admin')
      expect(Connecta::Scope::AccessAudit.where(user_id: owner_nominal.id, surface: 'inbox', access_path: 'inbox_update', decision: 'allow').count)
        .to eq(1)
    end

    it 'admin nominal com papel de agente recebe 401 do nativo, sem allow indevido em inbox_update' do
      patch whatsapp_path, params: { name: 'Trocada pelo admin' }, headers: token_admin

      expect(response).to have_http_status(:unauthorized)
      expect(whatsapp_inbox.reload.name).to eq('WhatsApp Baileys')
      # c7b moveu a auditoria para depois da autorização: com 401 nativo nenhum
      # `allow` pode existir (antes o caso caracterizava o allow fantasma).
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, surface: 'inbox', access_path: 'inbox_update', decision: 'allow').count)
        .to eq(0)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, surface: 'inbox', access_path: 'inbox_update').count)
        .to eq(0)
    end

    it 'webhooks: administrador da conta lista (200); admin nominal com papel de agente recebe 401 do nativo' do
      get webhooks_path, headers: token_owner
      expect(response).to have_http_status(:ok)

      get webhooks_path, headers: token_admin
      expect(response).to have_http_status(:unauthorized)
    end

    it 'relatório agregado de agente: administrador da conta lê (200); admin nominal com papel de agente recebe 401 do nativo' do
      get summary_path, headers: token_owner
      expect(response).to have_http_status(:ok)

      get summary_path, headers: token_admin
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'mensagens agendadas na própria conversa' do
    it 'agente A lista e agenda mensagem na própria conversa; a mensagem fica com o conteúdo enviado' do
      get "#{conv_a_path}/scheduled_messages", headers: token_a
      expect(response).to have_http_status(:ok)

      scheduled = { content: 'lembrete do agente A', scheduled_at: 1.day.from_now.iso8601, status: 'pending' }

      expect do
        post "#{conv_a_path}/scheduled_messages", params: scheduled, headers: token_a
      end.to change(ScheduledMessage, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(ScheduledMessage.last).to have_attributes(conversation_id: conv_a.id, content: 'lembrete do agente A')
    end
  end

  describe 'contagem de não lidas com conversation_unread_counts desligada (padrão)' do
    it 'agentes A e B recebem 403 com erro de recurso desligado, sem bloco de contagem' do
      [token_a, token_b].each do |token|
        get "#{conversations_path}/unread_counts", headers: token

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)).to have_key('error')
        expect(JSON.parse(response.body)).not_to have_key('payload')
      end
    end
  end
end
