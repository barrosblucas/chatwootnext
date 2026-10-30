require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2-c8 (spike G0): o chat interno não lê conversas do núcleo (evidência g0/12), então busca, listagem e ações por id não devolvem
# conteúdo de mensagens da inbox marcada. O texto único da mensagem de conv_a é o alvo de todas as asserções de vazamento.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · chat interno sem conteúdo de conversa marcada (T0.2-c8)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:internal_search_path) { "/api/v1/accounts/#{account.id}/internal_chat/search" }
  let(:channel_messages_path) { "/api/v1/accounts/#{account.id}/internal_chat/channels/#{public_channel.id}/messages" }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_without_grant) { member_without_grant.create_new_auth_token }
  let!(:public_channel) { create(:internal_chat_channel, account: account, name: 'Geral') }
  let!(:conversation_message) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a, message_type: :outgoing,
                     content: 'pedido segredoalfa do caso A')
  end

  it 'agente B não encontra texto da conversa marcada na busca do chat interno' do
    get internal_search_path, params: { q: 'segredoalfa' }, headers: token_b

    expect(response).to have_http_status(:ok)
    expect(json['messages']).to eq([])
    expect(response.body).not_to include(conversation_message.content)
  end

  it 'membro sem grant não encontra texto da conversa marcada na busca do chat interno' do
    get internal_search_path, params: { q: 'segredoalfa' }, headers: token_without_grant

    expect(response).to have_http_status(:ok)
    expect(json['messages']).to eq([])
    expect(response.body).not_to include(conversation_message.content)
  end

  it 'controle positivo: a busca acha a mensagem interna com o mesmo termo e não traz a da conversa' do
    internal_message = create(:internal_chat_message, account: account, channel: public_channel, sender: agent_b,
                                                      content: 'retorno segredoalfa interno')

    get internal_search_path, params: { q: 'segredoalfa' }, headers: token_b

    expect(json['messages'].pluck('id')).to eq([internal_message.id])
    expect(response.body).not_to include(conversation_message.content)
  end

  it 'agente B lista o canal público sem conteúdo da conversa marcada' do
    create(:internal_chat_message, account: account, channel: public_channel, sender: agent_a, content: 'oi equipe')

    get channel_messages_path, headers: token_b

    expect(response).to have_http_status(:ok)
    expect(json['messages'].pluck('content')).to eq(['oi equipe'])
    expect(response.body).not_to include(conversation_message.content)
  end

  it 'resposta com parent_id de mensagem da conversa marcada é recusada e nada é gravado' do
    expect do
      post channel_messages_path, params: { content: 'resposta', parent_id: conversation_message.id }, headers: token_b
    end.not_to change(InternalChat::Message, :count)

    expect(response).to have_http_status(:not_found)
  end

  it 'reação em mensagem da conversa marcada responde 404 e não grava reação' do
    expect do
      post "/api/v1/accounts/#{account.id}/internal_chat/messages/#{conversation_message.id}/reactions",
           params: { emoji: '+1' }, headers: token_b
    end.not_to change(InternalChat::Reaction, :count)

    expect(response).to have_http_status(:not_found)
  end
end
