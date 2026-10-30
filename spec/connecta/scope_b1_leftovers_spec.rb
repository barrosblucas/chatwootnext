require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 parte B1-leftovers (spike G0): 11 sub-rotas de conversa ainda sem exemplo individual.
# Rotas reais em config/routes.rb (api v1, escopo de conta): scheduled_messages (index/create/update/destroy),
# recurring_scheduled_messages (index/create/update/destroy), reactions (create sob messages),
# direct_uploads (create sob conversations), custom_attributes/mute/unmute/presence_subscribe/
# update_last_seen/toggle_typing_status/unread (member POST de conversations).
# Mesmo fixture das partes A/B1/B2. Políticas, queries e hooks são os reais; nenhum resultado de Gate é mockado.
# Stubs mínimos só em transporte externo (reação Baileys e presença) e no dispatcher de digitação.
# direct_uploads passa por guarda test-only Connecta::Scope::DirectUploadsHook (leitura 404 / escrita 403).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Agrupamento por superfície (lote B1): o cop RSpec/MultipleMemoizedHelpers conta 16 helpers
# (limite 14 do repo em .rubocop.yml:204-205); quebrar o grupo exigiria mover exemplos entre
# arquivos, o que reduziria a clareza da matriz B1 sem mudar autorização/contagem/efeito.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe 'Connecta G0 · sub-rotas B1 restantes (T0.2 leftovers)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:conv_a_path) { "#{conversations_path}/#{conv_a.display_id}" }
  let(:conv_control_path) { "#{conversations_path}/#{conv_control.display_id}" }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_member) { member_without_grant.create_new_auth_token }
  let(:token_manager) { manager_a.create_new_auth_token }
  let(:scheduled_base) { "#{conv_a_path}/scheduled_messages" }
  let(:recurring_base) { "#{conv_a_path}/recurring_scheduled_messages" }
  let(:reactions_path) do
    "#{conv_a_path}/messages/#{target_message.id}/reactions"
  end
  let(:direct_uploads_path) { "#{conv_a_path}/direct_uploads" }
  let(:blob_params) do
    { blob: { filename: 'a.png', byte_size: '1234', checksum: 'dGVzdA==', content_type: 'image/png' } }
  end

  let!(:target_message) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                     content: 'alvo de reacao', source_id: 'wamid-alvo-b1')
  end
  let!(:private_target) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                     content: 'nota privada', private: true)
  end
  let!(:scheduled_owned) do
    create(:scheduled_message, account: account, inbox: whatsapp_inbox, conversation: conv_a, author: agent_a)
  end
  let!(:recurring_owned) do
    create(:recurring_scheduled_message, account: account, inbox: whatsapp_inbox, conversation: conv_a, author: agent_a)
  end

  before do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                     sender: contact_a, message_type: :incoming, content: 'oi de A')
    allow_any_instance_of(Whatsapp::Providers::WhatsappBaileysService).to receive(:send_message).and_return('msg_id') # rubocop:disable RSpec/AnyInstance
  end

  describe 'scheduled_messages (GET/update/destroy; create negado já coberto na B1)' do
    it 'outro setor e membro sem grant não listam agendadas de A (404), sem vazar conteúdo' do
      [token_b, token_member].each do |token|
        get scheduled_base, headers: token

        expect(response).to have_http_status(:not_found)
      end
      expect(response.body).not_to include(scheduled_owned.content)
    end

    it 'gestor lê agendadas de A, mas não atualiza nem apaga (403), sem alterar nada' do
      get scheduled_base, headers: token_manager
      expect(response).to have_http_status(:ok)

      patch "#{scheduled_base}/#{scheduled_owned.id}", params: { content: 'gestor' }, headers: token_manager, as: :json
      expect(response).to have_http_status(:forbidden)

      expect do
        delete "#{scheduled_base}/#{scheduled_owned.id}", headers: token_manager
      end.not_to change(ScheduledMessage, :count)
      expect(response).to have_http_status(:forbidden)
      expect(scheduled_owned.reload.content).not_to eq('gestor')
    end

    it 'agente com grant atualiza e apaga a própria agendada' do
      patch "#{scheduled_base}/#{scheduled_owned.id}", params: { content: 'novo conteudo' }, headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(scheduled_owned.reload.content).to eq('novo conteudo')

      expect do
        delete "#{scheduled_base}/#{scheduled_owned.id}", headers: token_a
      end.to change(ScheduledMessage, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'recurring_scheduled_messages (index/update/destroy; create negado já coberto na B2)' do
    it 'outro setor e membro sem grant não listam recorrências de A (404)' do
      [token_b, token_member].each do |token|
        get recurring_base, headers: token

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'gestor não atualiza recorrência de A (403), sem alterar conteúdo' do
      patch "#{recurring_base}/#{recurring_owned.id}", params: { content: 'gestor' }, headers: token_manager, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(recurring_owned.reload.content).not_to eq('gestor')
    end

    it 'agente com grant lista e cancela a própria recorrência' do
      get recurring_base, headers: token_a
      expect(response).to have_http_status(:ok)

      delete "#{recurring_base}/#{recurring_owned.id}", headers: token_a

      expect(response).to have_http_status(:ok)
      expect(recurring_owned.reload.status).to eq('cancelled')
    end

    it 'controle de inbox não marcada lista recorrências nativamente' do
      get "#{conv_control_path}/recurring_scheduled_messages", headers: token_a

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'reactions (POST messages/:message_id/reactions, canal baileys suporta)' do
    it 'outro setor e membro sem grant recebem 404 sem criar reação' do
      [token_b, token_member].each do |token|
        expect do
          post reactions_path, params: { emoji: '👍' }, headers: token, as: :json
        end.not_to change(Message, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'gestor não reage em conversa de A (403), sem criar reação nem enfileirar envio' do
      expect do
        post reactions_path, params: { emoji: '👍' }, headers: token_manager, as: :json

        expect(response).to have_http_status(:forbidden)
      end.not_to change(Message, :count)

      expect do
        post reactions_path, params: { emoji: '👍' }, headers: token_manager, as: :json

        expect(response).to have_http_status(:forbidden)
      end.not_to have_enqueued_job(SendReplyJob)
    end

    it 'agente com grant reage em nota privada de A (sem saída ao provedor)' do
      private_path = "#{conv_a_path}/messages/#{private_target.id}/reactions"

      expect do
        post private_path, params: { emoji: '👍' }, headers: token_a, as: :json
      end.to change(Message, :count).by(1)

      expect(response).to have_http_status(:ok)
      created = conv_a.messages.order(:id).last
      expect(created.content).to eq('👍')
      expect(created.content_attributes['is_reaction']).to be(true)
    end

    it 'controle de inbox não marcada segue nativo (canal sem reações responde 422, sem ACL 404/403)' do
      control_message = create(:message, account: account, inbox: control_inbox, conversation: conv_control, content: 'alvo controle')
      post "#{conv_control_path}/messages/#{control_message.id}/reactions", params: { emoji: '👍' }, headers: token_a, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'direct_uploads (POST conversations/:id/direct_uploads)' do
    it 'outro setor e membro sem grant recebem 404 sem criar blob nem emitir URL' do
      [token_b, token_member].each do |token|
        expect do
          post direct_uploads_path, params: blob_params, headers: token, as: :json
        end.not_to change(ActiveStorage::Blob, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'gestor recebe 403 sem criar blob' do
      expect do
        post direct_uploads_path, params: blob_params, headers: token_manager, as: :json
      end.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'agente com grant cria blob e controle de inbox não marcada cria nativamente' do
      expect do
        post direct_uploads_path, params: blob_params, headers: token_a, as: :json
      end.to change(ActiveStorage::Blob, :count).by(1)
      expect(response).to have_http_status(:success)

      expect do
        post "#{conv_control_path}/direct_uploads", params: blob_params, headers: token_a, as: :json
      end.to change(ActiveStorage::Blob, :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'custom_attributes (POST conversations/:id/custom_attributes; positivo do agente já coberto na B2)' do
    it 'outro setor e membro sem grant recebem 404 e o valor não muda' do
      conv_a.update!(custom_attributes: { 'setor' => 'A' })

      [token_b, token_member].each do |token|
        post "#{conv_a_path}/custom_attributes", params: { custom_attributes: { setor: 'B' } }, headers: token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      expect(conv_a.reload.custom_attributes).to eq('setor' => 'A')
    end

    it 'controle de inbox não marcada atualiza atributos nativamente' do
      post "#{conv_control_path}/custom_attributes", params: { custom_attributes: { setor: 'controle' } }, headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(conv_control.reload.custom_attributes).to eq('setor' => 'controle')
    end
  end

  describe 'mute (POST conversations/:id/mute)' do
    it 'outro setor e membro sem grant recebem 404, sem silenciar nem resolver' do
      [token_b, token_member].each do |token|
        expect do
          post "#{conv_a_path}/mute", headers: token, as: :json
        end.not_to change(Message, :count)

        expect(response).to have_http_status(:not_found)
      end

      expect(conv_a.reload.status).to eq('open')
      expect(conv_a.reload.muted?).to be(false)
    end

    it 'gestor recebe 403 ao silenciar, sem silenciar nem resolver' do
      expect do
        post "#{conv_a_path}/mute", headers: token_manager, as: :json
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('open')
      expect(conv_a.reload.muted?).to be(false)
    end

    it 'agente com grant silencia a própria conversa' do
      post "#{conv_a_path}/mute", headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.resolved?).to be(true)
      expect(conv_a.reload.muted?).to be(true)
    end
  end

  describe 'unmute (POST conversations/:id/unmute)' do
    before { conv_a.mute! }

    it 'outro setor e membro sem grant recebem 404 e a conversa segue silenciada' do
      [token_b, token_member].each do |token|
        post "#{conv_a_path}/unmute", headers: token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      expect(conv_a.reload.muted?).to be(true)
    end

    it 'gestor recebe 403 ao remover silêncio, sem alterar' do
      post "#{conv_a_path}/unmute", headers: token_manager, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.muted?).to be(true)
    end

    it 'agente com grant remove o silêncio da própria conversa' do
      post "#{conv_a_path}/unmute", headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.muted?).to be(false)
    end
  end

  describe 'presence_subscribe (POST conversations/:id/presence_subscribe)' do
    it 'outro setor e membro sem grant recebem 404 e nada é enviado ao transporte' do
      [token_b, token_member].each do |token|
        post "#{conv_a_path}/presence_subscribe", headers: token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'gestor recebe 403 sem acionar o serviço de presença' do
      expect(Conversations::PresenceSubscribeService).not_to receive(:new)

      post "#{conv_a_path}/presence_subscribe", headers: token_manager, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'agente com grant assina presença da própria conversa sem I/O externo' do
      post "#{conv_a_path}/presence_subscribe", headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'controle de inbox não marcada assina presença nativamente' do
      post "#{conv_control_path}/presence_subscribe", headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'presence_subscribe_bulk (POST conversations/presence_subscribe_bulk)' do
    let(:bulk_path) { "#{conversations_path}/presence_subscribe_bulk" }

    before do
      stub_request(:any, /.*/).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    it 'outro setor e membro sem grant negados sem serviço/provedor' do
      expect(Conversations::PresenceSubscribeService).not_to receive(:new)

      [token_b, token_member].each do |token|
        post bulk_path, params: { conversation_ids: [conv_a.display_id] }, headers: token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'gestor conforme gate unitário recebe 403 sem acionar o serviço de presença' do
      expect(Conversations::PresenceSubscribeService).not_to receive(:new)

      post bulk_path, params: { conversation_ids: [conv_a.display_id] }, headers: token_manager, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'pedido misto permitido+proibido nega antes de efeitos' do
      expect(Conversations::PresenceSubscribeService).not_to receive(:new)

      post bulk_path, params: { conversation_ids: [conv_a.display_id, conv_b.display_id] }, headers: token_a, as: :json

      expect(response).to have_http_status(:not_found)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'agente autorizado assina bulk da própria conversa sem I/O externo' do
      post bulk_path, params: { conversation_ids: [conv_a.display_id] }, headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'controle de inbox não marcada segue nativo' do
      post bulk_path, params: { conversation_ids: [conv_control.display_id] }, headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'update_last_seen (POST conversations/:id/update_last_seen)' do
    it 'outro setor e membro sem grant recebem 404 sem tocar no relógio de leitura' do
      [token_b, token_member].each do |token|
        expect do
          post "#{conv_a_path}/update_last_seen", headers: token, as: :json
        end.not_to(change { conv_a.reload.agent_last_seen_at })

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'gestor recebe 403 sem tocar no relógio de leitura' do
      expect do
        post "#{conv_a_path}/update_last_seen", headers: token_manager, as: :json
      end.not_to(change { conv_a.reload.agent_last_seen_at })

      expect(response).to have_http_status(:forbidden)
    end

    it 'agente com grant atualiza a leitura da própria conversa com mensagem não lida' do
      post "#{conv_a_path}/update_last_seen", headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.agent_last_seen_at).to be_present
    end
  end

  describe 'toggle_typing_status (POST conversations/:id/toggle_typing_status)' do
    it 'outro setor e membro sem grant recebem 404 sem despachar digitação' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      [token_b, token_member].each do |token|
        post "#{conv_a_path}/toggle_typing_status", params: { typing_status: 'on', is_private: false }, headers: token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
    end

    it 'gestor recebe 403 sem despachar digitação' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post "#{conv_a_path}/toggle_typing_status", params: { typing_status: 'on', is_private: false }, headers: token_manager,
                                                  as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
    end

    it 'agente com grant difunde digitação da própria conversa' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      post "#{conv_a_path}/toggle_typing_status", params: { typing_status: 'on', is_private: false }, headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
    end

    it 'controle de inbox não marcada difunde digitação nativamente' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      post "#{conv_control_path}/toggle_typing_status", params: { typing_status: 'on', is_private: false }, headers: token_a,
                                                        as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'unread (POST conversations/:id/unread, ação de membro)' do
    it 'outro setor e membro sem grant recebem 404 sem despachar nem relogar leitura' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      before_seen = conv_a.reload.agent_last_seen_at

      [token_b, token_member].each do |token|
        post "#{conv_a_path}/unread", headers: token, as: :json

        expect(response).to have_http_status(:not_found)
      end

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      expect(conv_a.reload.agent_last_seen_at).to eq(before_seen)
    end

    it 'gestor recebe 403 sem despachar nem relogar leitura' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      before_seen = conv_a.reload.agent_last_seen_at

      post "#{conv_a_path}/unread", headers: token_manager, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      expect(conv_a.reload.agent_last_seen_at).to eq(before_seen)
    end

    it 'agente com grant marca a própria conversa como não lida' do
      post "#{conv_a_path}/unread", headers: token_a, as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
