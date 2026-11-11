require 'rails_helper'

# Etapa 3 · opt-out do bot por número. O fork lê/altera no WP (autoridade) e
# espelha em contact.custom_attributes['connecta_bot_disabled']. Usa as
# tabelas de produto (Connecta::ScopedInbox), sem o ambiente especial G0.
RSpec.describe 'Connecta Bot Opt-out API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:platform) { instance_double(Connecta::Runtime::PlatformClient) }

  def bot_optout_path(conv = conversation)
    "/api/v1/accounts/#{account.id}/conversations/#{conv.display_id}/connecta_bot_optout"
  end

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(platform)
    Connecta::ScopedInbox.create!(inbox_id: conversation.inbox.id)
  end

  describe 'GET show' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get bot_optout_path

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent from another account' do
      let(:other_agent) { create(:user, account: create(:account), role: :agent) }

      it 'returns unauthorized' do
        get bot_optout_path, headers: other_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the agent has no access to the inbox' do
      let(:outsider) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        get bot_optout_path, headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the conversation does not exist' do
      it 'returns not found' do
        get "/api/v1/accounts/#{account.id}/conversations/99999/connecta_bot_optout",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the inbox is not Connecta-scoped' do
      before do
        Connecta::ScopedInbox.where(inbox_id: conversation.inbox_id).delete_all
        allow(platform).to receive(:get).and_return({ 'disabled' => false })
      end

      it 'returns not found without calling the platform' do
        get bot_optout_path, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to be_present
        expect(platform).not_to have_received(:get)
      end
    end

    context 'when the platform answers' do
      before do
        allow(platform).to receive(:get).and_return({ 'disabled' => true, 'contact_id' => 42 })
      end

      it 'returns the disabled state with account and display_id in the query' do
        get bot_optout_path, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['disabled']).to be(true)
        expect(platform).to have_received(:get) do |path|
          query = URI.decode_www_form(URI(path).query).to_h
          expect(query['account_id']).to eq(account.id.to_s)
          expect(query['conversation_id']).to eq(conversation.display_id.to_s)
        end
      end
    end

    context 'when the platform is unreachable' do
      before do
        allow(platform).to receive(:get)
          .and_raise(Connecta::Runtime::PlatformClient::Error.new('Connecta platform unavailable', status: :gateway_timeout))
      end

      it 'returns service unavailable with a friendly message' do
        get bot_optout_path, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.conversations.connecta_bot_optout.timeout'))
      end
    end
  end

  describe 'POST create' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post bot_optout_path, params: { disabled: true }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when disabled is missing' do
      it 'returns unprocessable entity' do
        post bot_optout_path, params: {}, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(platform).not_to have_received(:post)
      end
    end

    context 'when disabling the bot' do
      before do
        allow(platform).to receive(:post).and_return({ 'disabled' => true, 'contact_id' => conversation.contact_id })
      end

      it 'posts display_id, account, state and actor, then mirrors the flag on the contact', :aggregate_failures do
        post bot_optout_path, params: { disabled: true }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['disabled']).to be(true)
        expect(platform).to have_received(:post).with(
          '/attendance/v1/bot-optout',
          hash_including(account_id: account.id, conversation_id: conversation.display_id,
                         disabled: true, actor_chatwoot_user_id: agent.id)
        )
        expect(conversation.contact.reload.custom_attributes['connecta_bot_disabled']).to be(true)
      end
    end

    context 'when re-enabling the bot' do
      before do
        conversation.contact.update!(custom_attributes: { 'connecta_bot_disabled' => true, 'other' => 'kept' })
        allow(platform).to receive(:post).and_return({ 'disabled' => false, 'contact_id' => conversation.contact_id })
      end

      it 'removes the flag and keeps other custom attributes', :aggregate_failures do
        post bot_optout_path, params: { disabled: false }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['disabled']).to be(false)
        attrs = conversation.contact.reload.custom_attributes
        expect(attrs.key?('connecta_bot_disabled')).to be(false)
        expect(attrs['other']).to eq('kept')
      end
    end

    context 'when the platform rejects with not_human_service_inbox' do
      before do
        allow(platform).to receive(:post)
          .and_raise(Connecta::Runtime::PlatformClient::Error.new('not_human_service_inbox', status: :unprocessable_entity))
      end

      it 'returns unprocessable entity with a friendly message and no local mirror', :aggregate_failures do
        post bot_optout_path, params: { disabled: true }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error'])
          .to eq(I18n.t('errors.conversations.connecta_bot_optout.not_human_service_inbox'))
        expect(conversation.contact.reload.custom_attributes['connecta_bot_disabled']).to be_nil
      end
    end
  end
end
