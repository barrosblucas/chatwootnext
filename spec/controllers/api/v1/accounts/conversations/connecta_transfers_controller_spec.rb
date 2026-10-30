require 'rails_helper'

RSpec.describe 'Connecta Transfer API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:gateway_url) { 'https://connecta-gateway.example.com' }
  let(:transfer_secret) { 'connecta-transfer-secret-value' }

  def enable_connecta_transfer!(enabled: true)
    InstallationConfig.find_or_create_by!(name: 'CONNECTA_TRANSFER_ENABLED').update!(value: enabled)
    InstallationConfig.find_or_create_by!(name: 'CONNECTA_GATEWAY_URL').update!(value: gateway_url)
    InstallationConfig.find_or_create_by!(name: 'CONNECTA_TRANSFER_SECRET').update!(value: transfer_secret)
    GlobalConfig.clear_cache
  end

  describe 'GET /api/v1/accounts/:account_id/conversations/:conversation_id/connecta_transfer/destinations' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get api_v1_account_conversation_connecta_transfer_destinations_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        )

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent from another account' do
      let(:other_account) { create(:account) }
      let(:other_agent) { create(:user, account: other_account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns unauthorized' do
        get api_v1_account_conversation_connecta_transfer_destinations_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
            headers: other_agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the conversation does not exist' do
      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        enable_connecta_transfer!
      end

      it 'returns not found' do
        get api_v1_account_conversation_connecta_transfer_destinations_url(
          account_id: account.id,
          conversation_id: 99_999
        ),
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when Connecta transfer is disabled' do
      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        enable_connecta_transfer!(enabled: false)
      end

      it 'returns forbidden' do
        get api_v1_account_conversation_connecta_transfer_destinations_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to be_present
        expect(response.body).not_to include(transfer_secret)
      end
    end

    context 'when Connecta transfer is enabled' do
      let(:destinations_payload) do
        {
          destinations: [
            {
              departmentId: 'vs.ubs-01',
              displayName: 'UBS Centro',
              inboxId: 15,
              teamId: 3
            }
          ]
        }
      end

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        enable_connecta_transfer!
      end

      it 'returns destinations from the gateway' do
        stub_request(:get, "#{gateway_url}/chatwoot/transfer/destinations")
          .with(
            query: {
              from_inbox_id: conversation.inbox_id.to_s,
              account_id: account.id.to_s
            },
            headers: { 'Authorization' => "Bearer #{transfer_secret}" }
          ).to_return(status: 200, body: destinations_payload.to_json)

        get api_v1_account_conversation_connecta_transfer_destinations_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['destinations']).to eq(destinations_payload[:destinations].as_json)
        expect(response.body).not_to include(transfer_secret)
      end

      it 'returns gateway timeout when the gateway does not respond' do
        stub_request(:get, "#{gateway_url}/chatwoot/transfer/destinations")
          .with(
            query: {
              from_inbox_id: conversation.inbox_id.to_s,
              account_id: account.id.to_s
            }
          ).to_timeout

        get api_v1_account_conversation_connecta_transfer_destinations_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:gateway_timeout)
        expect(response.body).not_to include(transfer_secret)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/connecta_transfer' do
    let(:target_department_id) { 'vs.ubs-01' }
    let(:transfer_response) do
      {
        new_conversation_id: 57,
        display_id: 57,
        target_department_id: target_department_id,
        source_resolved: true
      }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_connecta_transfer_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
             params: { target_department_id: target_department_id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent from another account' do
      let(:other_account) { create(:account) }
      let(:other_agent) { create(:user, account: other_account, role: :agent) }

      it 'returns unauthorized' do
        post api_v1_account_conversation_connecta_transfer_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
             params: { target_department_id: target_department_id },
             headers: other_agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the conversation does not exist' do
      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        enable_connecta_transfer!
      end

      it 'returns not found' do
        post api_v1_account_conversation_connecta_transfer_url(
          account_id: account.id,
          conversation_id: 99_999
        ),
             params: { target_department_id: target_department_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when Connecta transfer is enabled' do
      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        enable_connecta_transfer!
      end

      it 'proxies the transfer to the gateway', :aggregate_failures do
        stub_request(:post, "#{gateway_url}/chatwoot/transfer")
          .with(
            headers: {
              'Authorization' => "Bearer #{transfer_secret}",
              'Content-Type' => 'application/json'
            }
          ) do |request|
            body = JSON.parse(request.body)
            expect(body['transfer_id']).to match(
              /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
            )
            expect(body['account_id']).to eq(account.id)
            expect(body['source_conversation_id']).to eq(conversation.display_id)
            expect(body['target_department_id']).to eq(target_department_id)
            expect(body['agent']).to eq({ 'id' => agent.id, 'email' => agent.email })
          end.to_return(status: 200, body: transfer_response.to_json)

        post api_v1_account_conversation_connecta_transfer_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
             params: { target_department_id: target_department_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to include(
          'new_conversation_id' => 57,
          'display_id' => 57,
          'target_department_id' => target_department_id,
          'source_resolved' => true
        )
        expect(response.body).not_to include(transfer_secret)
      end

      it 'returns unprocessable entity when target_department_id is blank' do
        post api_v1_account_conversation_connecta_transfer_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
             params: { target_department_id: '' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(response.body).not_to include(transfer_secret)
        expect(WebMock).not_to have_requested(:post, "#{gateway_url}/chatwoot/transfer")
      end

      it 'maps gateway conflict to 409' do
        stub_request(:post, "#{gateway_url}/chatwoot/transfer")
          .to_return(status: 409, body: { error: 'duplicate transfer' }.to_json)

        post api_v1_account_conversation_connecta_transfer_url(
          account_id: account.id,
          conversation_id: conversation.display_id
        ),
             params: { target_department_id: target_department_id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['error']).to eq('duplicate transfer')
        expect(response.body).not_to include(transfer_secret)
      end
    end
  end
end
