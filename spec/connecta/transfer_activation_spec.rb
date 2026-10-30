require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_transfer_schema'

# T0.7a (spike G0): barreira de ativação. Depois do commit local o destino nasce pending_activation: agentes do destino não veem nem
# operam; a mensagem do cidadão entra no destino pelo IncomingHook real; só a versão confirmada ativa; a origem nunca reabre.
# Transacional e na mesma thread: o lock de (inbox, contato) é tomado na mesma sessão. Gate, policies e hooks são os reais.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta G0 · barreira de ativação da transferência (T0.7a)', type: :request do
  include_context 'with connecta g0 scope fixture'

  # Canal Baileys sem rede: o token de verificação é gravado sem validar credenciais (mesmo caminho do T0.3).
  # Recibos de leitura e foto de perfil são o transporte externo, stubado; a decisão de acesso não é.
  before do
    stub_request(:get, /profile-picture-url/).to_return(status: 200, body: { data: { profilePictureUrl: nil } }.to_json)
    stub_request(:post, /send-receipts/).to_return(status: 200, body: '')
    whatsapp_channel.provider_config = { 'webhook_verify_token' => token }
    whatsapp_channel.save!(validate: false)
    whatsapp_inbox.update!(enable_auto_assignment: false)
  end

  let(:token) { 'valid_token' }
  let(:run_digits) { format('%08d', SecureRandom.random_number(10**8)) }
  let(:lid_jid) { "9#{run_digits}@lid" }
  let(:phone_jid) { "5511#{run_digits}@s.whatsapp.net" }
  let(:summary) { 'Assunto: segunda via. Feito: dados conferidos. Pendencia: retorno do setor B.' }

  # Mensagem de contato individual (LID com JID de telefone), no formato do messages.upsert do baileys-api.
  let(:deliver) do
    lambda do |source_id|
      params = {
        webhookVerifyToken: token,
        event: 'messages.upsert',
        data: {
          type: 'notify',
          messages: [{
            key: { id: source_id, remoteJid: lid_jid, remoteJidAlt: phone_jid, fromMe: false, addressingMode: 'lid' },
            pushName: 'Cidadao T07a',
            messageTimestamp: Time.current.to_i,
            message: { conversation: "texto #{source_id}" }
          }]
        }
      }
      Whatsapp::IncomingMessageBaileysService.new(inbox: whatsapp_inbox, params: params).perform
    end
  end

  # Primeira mensagem sem escopo: caminho nativo cria a conversa de origem; depois o escopo ativo é gravado para ela.
  let!(:origin_conversation) do
    deliver.call('msg-0')
    Message.find_by!(source_id: 'msg-0').conversation
  end
  let!(:origin_scope) do
    Connecta::Scope::ConversationScope.create!(conversation_id: origin_conversation.id, inbox_id: whatsapp_inbox.id,
                                               contact_id: origin_conversation.contact_id, org_unit: org_a, state: 'active',
                                               case_protocol: 'CASO-T07A', case_version: 1)
  end

  let(:transfer) { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b) }
  let(:destination) { Conversation.find(transfer.record.destination_conversation_id) }
  let(:destination_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: destination.id) }

  describe 'com destino em pending_activation (depois do commit local)' do
    before do
      transfer.begin!
      transfer.commit_local!(target_case_version: 2, summary: summary)
    end

    it 'mensagem do cidadão entra no destino e a origem continua transferred_out' do
      deliver.call('msg-pending')

      expect(Message.find_by!(source_id: 'msg-pending').conversation_id).to eq(destination.id)
      expect(origin_scope.reload.state).to eq('transferred_out')
      expect(destination_scope.reload.state).to eq('pending_activation')
    end

    it 'agente do destino recebe 404 na conversa e ela não aparece na lista' do
      deliver.call('msg-pending')

      get "#{conversations_path}/#{destination.display_id}", headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get conversations_path, headers: agent_b.create_new_auth_token
      expect(JSON.parse(response.body)['data']['payload'].pluck('id')).to contain_exactly(conv_b.display_id)
    end

    it 'admin nominal lê a conversa em pending_activation e a leitura fica auditada' do
      deliver.call('msg-pending')

      get "#{conversations_path}/#{destination.display_id}", headers: admin_nominal.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: destination.id, access_path: 'detail',
                                                decision: 'allow').count).to eq(1)
    end

    it 'activate! com versão diferente da confirmada é recusado e não muda nada' do
      expect { transfer.activate!(case_version: 1) }
        .to(raise_error { |error| expect(error.class.name).to eq('Connecta::Transfer::LocalTransaction::VersionMismatch') })

      expect(destination_scope.reload).to have_attributes(state: 'pending_activation', case_version: 0)
      expect(transfer.record.reload.state).to eq('committed_local')
    end

    it 'activate! repetido com a mesma versão é idempotente: mesmo destino, sem efeitos novos' do
      transfer.activate!(case_version: 2)
      first_destination_id = transfer.record.destination_conversation_id
      resumed = Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b)

      expect do
        transfer.activate!(case_version: 2)
        resumed.activate!(case_version: 2)
      end.not_to(change { [Connecta::Transfer::TransferRecord.count, Conversation.count, Message.count] })

      expect(transfer.record.reload).to have_attributes(state: 'committed', target_case_version: 2)
      expect(resumed.record).to have_attributes(state: 'committed', destination_conversation_id: first_destination_id)
      expect(destination_scope.reload).to have_attributes(state: 'active', case_version: 2)
      expect(destination.id).to eq(first_destination_id)
    end

    it 'activate! com versão diferente depois de ativo é recusado sem mudar nada' do
      transfer.activate!(case_version: 2)

      expect { transfer.activate!(case_version: 3) }
        .to(raise_error { |error| expect(error.class.name).to eq('Connecta::Transfer::LocalTransaction::VersionMismatch') })

      expect(transfer.record.reload).to have_attributes(state: 'committed', target_case_version: 2)
      expect(destination_scope.reload).to have_attributes(state: 'active', case_version: 2)
      expect(origin_scope.reload.state).to eq('transferred_out')
    end

    it 'activate! com a versão confirmada: agente do destino vê a conversa com a nota de resumo' do
      transfer.activate!(case_version: 2)

      expect(destination_scope.reload).to have_attributes(state: 'active', case_version: 2)
      expect(transfer.record.reload.state).to eq('committed')
      get "#{conversations_path}/#{destination.display_id}/messages", headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(summary)
    end

    it 'mark_stuck! deixa o destino só para admin e a origem continua transferred_out' do
      transfer.mark_stuck!

      expect(destination_scope.reload.state).to eq('activation_stuck')
      expect(transfer.record.reload.state).to eq('activation_stuck')
      get "#{conversations_path}/#{destination.display_id}", headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(origin_scope.reload.state).to eq('transferred_out')
    end

    it 'abort! depois do commit local lança erro e a origem continua transferred_out' do
      expect { transfer.abort! }.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotFound') })

      expect(origin_scope.reload.state).to eq('transferred_out')
      expect(origin_conversation.reload.status).to eq('resolved')
      expect(transfer.record.reload.state).to eq('committed_local')
    end

    # Origem sem acesso para o agente de A: a leitura falha antes da escrita, então a resposta é 404 e nada é criado.
    it 'agente de A não cria mensagem na origem' do
      path = "#{conversations_path}/#{origin_conversation.display_id}/messages"
      headers = agent_a.create_new_auth_token

      expect { post path, params: { content: 'tentativa' }, headers: headers }.not_to change(Message, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'toggle_status para open na origem é negado ao agente de A e ao admin nominal' do
      path = "#{conversations_path}/#{origin_conversation.display_id}/toggle_status"

      post path, params: { status: 'open' }, headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      post path, params: { status: 'open' }, headers: admin_nominal.create_new_auth_token
      expect(response).to have_http_status(:forbidden)

      expect(origin_conversation.reload.status).to eq('resolved')
    end
  end

  describe 'com transferência só iniciada' do
    it 'begin! e abort! devolvem a origem a active e o registro a aborted' do
      transfer.begin!
      expect(origin_scope.reload.state).to eq('transferring')

      transfer.abort!

      expect(origin_scope.reload.state).to eq('active')
      expect(transfer.record.reload.state).to eq('aborted')
    end
  end
end
