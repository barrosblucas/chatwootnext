require 'rails_helper'

# Fase 1 do vínculo simplificado: WP chama o fork (HMAC) para provisionar o
# agente, trocar a senha e desativar o vínculo. Contrato de fio v1 em
# app/controllers/connecta/v1/users_controller.rb.
RSpec.describe 'Connecta v1 users provisioning', type: :request do
  let(:secret) { 'test-platform-to-fork-secret' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def signed_headers(timestamp, request_path, request_body)
    canonical = [timestamp, 'POST', request_path, request_body].join('.')
    {
      'X-Connecta-Timestamp' => timestamp,
      'X-Connecta-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)}",
      'Content-Type' => 'application/json'
    }
  end

  def post_signed(path, body_hash, at: Time.current)
    body = body_hash.to_json
    post path, params: body, headers: signed_headers(at.to_i.to_s, path, body)
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => account.id.to_s,
                        'CONNECTA_PLATFORM_TO_FORK_SECRET' => secret
                      ))
    Connecta::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
  end

  describe 'POST /connecta/v1/users/provision' do
    let(:path) { '/connecta/v1/users/provision' }

    it 'creates the user, the agent membership and the scoped inbox membership' do
      post_signed(path, { account_id: account.id, email: '  New.Agent@Example.com ', name: 'New Agent', password: 'StrongPass123!' })

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['user_created']).to be(true)
      expect(body['membership_created']).to be(true)
      expect(body['role']).to eq('agent')
      expect(body['inbox_ids_added']).to eq([inbox.id])

      user = User.find(body['chatwoot_user_id'])
      expect(user.email).to eq('new.agent@example.com')
      expect(user.account_users.find_by(account_id: account.id)).to be_agent
      expect(InboxMember.exists?(inbox_id: inbox.id, user_id: user.id)).to be(true)
    end

    it 'works without a password (generates a strong one)' do
      post_signed(path, { account_id: account.id, email: 'nopass@example.com', name: 'No Pass' })

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['user_created']).to be(true)
    end

    it 'reuses an existing user without changing password or name, and is idempotent' do
      existing = create(:user, email: 'reuse@example.com', name: 'Original', password: 'OriginalPass123!')

      post_signed(path, { account_id: account.id, email: 'reuse@example.com', name: 'Changed', password: 'OtherPass123!' })
      expect(response).to have_http_status(:ok)
      first = JSON.parse(response.body)
      expect(first['chatwoot_user_id']).to eq(existing.id)
      expect(first['membership_created']).to be(true)

      post_signed(path, { account_id: account.id, email: 'reuse@example.com', name: 'Changed', password: 'OtherPass123!' })
      expect(response).to have_http_status(:ok)
      second = JSON.parse(response.body)
      expect(second['chatwoot_user_id']).to eq(existing.id)
      expect(second['user_created']).to be(false)
      expect(second['membership_created']).to be(false)
      expect(second['inbox_ids_added']).to eq([])

      expect(existing.reload.name).to eq('Original')
      expect(existing.valid_password?('OriginalPass123!')).to be(true)
    end

    it 'keeps the administrator role of an existing membership' do
      admin = create(:user, :administrator, account: account)

      post_signed(path, { account_id: account.id, email: admin.email, name: admin.name })
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['membership_created']).to be(false)
      expect(body['role']).to eq('administrator')
      expect(admin.account_users.find_by(account_id: account.id)).to be_administrator
    end

    it 'does not add the agent to admin_only scoped inboxes' do
      admin_only_inbox = create(:inbox, account: account)
      Connecta::ScopedInbox.create!(inbox_id: admin_only_inbox.id, enforcement: 'admin_only', maintenance: false)

      post_signed(path, { account_id: account.id, email: 'scoped@example.com', name: 'Scoped' })
      expect(response).to have_http_status(:ok)
      user_id = JSON.parse(response.body)['chatwoot_user_id']
      expect(InboxMember.exists?(inbox_id: admin_only_inbox.id, user_id: user_id)).to be(false)
      expect(InboxMember.exists?(inbox_id: inbox.id, user_id: user_id)).to be(true)
    end

    it 'rejects a missing signature with 401' do
      post path, params: { account_id: account.id, email: 'x@example.com', name: 'X' }.to_json,
                headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a divergent account_id with 403' do
      post_signed(path, { account_id: account.id + 1, email: 'x@example.com', name: 'X' })
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /connecta/v1/users/:user_id/password' do
    it 'changes the agent password, confirms the user and clears tokens' do
      agent = create(:user, password: 'OldPassword123!', account: account)
      agent.update!(tokens: { 'client' => { 'token' => 'abc', 'expiry' => 1.hour.from_now.to_i } })

      post_signed("/connecta/v1/users/#{agent.id}/password", { account_id: account.id, password: 'BrandNewPass123!' })
      expect(response).to have_http_status(:no_content)

      agent.reload
      expect(agent.valid_password?('BrandNewPass123!')).to be(true)
      expect(agent.tokens).to eq({})
    end

    it 'refuses an administrator with 409 not_agent' do
      admin = create(:user, :administrator, account: account)

      post_signed("/connecta/v1/users/#{admin.id}/password", { account_id: account.id, password: 'BrandNewPass123!' })
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('not_agent')
      expect(admin.reload.valid_password?('Password1!')).to be(true)
    end

    it 'returns 404 for a user outside the account' do
      outsider = create(:user)

      post_signed("/connecta/v1/users/#{outsider.id}/password", { account_id: account.id, password: 'BrandNewPass123!' })
      expect(response).to have_http_status(:not_found)
    end

    it 'rejects a short password with 422' do
      agent = create(:user, account: account)

      post_signed("/connecta/v1/users/#{agent.id}/password", { account_id: account.id, password: 'short' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('invalid_password')
    end
  end

  describe 'POST /connecta/v1/users/:user_id/deactivate' do
    it 'removes the membership and inbox rows, keeps the user, clears tokens' do
      agent = create(:user, account: account)
      create(:inbox_member, inbox: inbox, user: agent)
      other_inbox = create(:inbox, account: create(:account))
      create(:inbox_member, inbox: other_inbox, user: agent)
      agent.update!(tokens: { 'client' => { 'token' => 'abc', 'expiry' => 1.hour.from_now.to_i } })

      post_signed("/connecta/v1/users/#{agent.id}/deactivate", { account_id: account.id })
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({ 'deactivated' => true })

      expect(AccountUser.exists?(account_id: account.id, user_id: agent.id)).to be(false)
      expect(InboxMember.exists?(inbox_id: inbox.id, user_id: agent.id)).to be(false)
      expect(InboxMember.exists?(inbox_id: other_inbox.id, user_id: agent.id)).to be(true)
      expect(User.exists?(agent.id)).to be(true)
      expect(agent.reload.tokens).to eq({})
    end

    it 'is idempotent when the membership is already gone' do
      agent = create(:user)

      post_signed("/connecta/v1/users/#{agent.id}/deactivate", { account_id: account.id })
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({ 'already_inactive' => true })
    end

    it 'refuses an administrator with 409 not_agent' do
      admin = create(:user, :administrator, account: account)

      post_signed("/connecta/v1/users/#{admin.id}/deactivate", { account_id: account.id })
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)['error']).to eq('not_agent')
      expect(AccountUser.exists?(account_id: account.id, user_id: admin.id)).to be(true)
    end

    it 'reactivates by provisioning again' do
      agent = create(:user, email: 'back@example.com', account: account)

      post_signed("/connecta/v1/users/#{agent.id}/deactivate", { account_id: account.id })
      expect(response).to have_http_status(:ok)

      post_signed('/connecta/v1/users/provision', { account_id: account.id, email: 'back@example.com', name: 'Back' })
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['chatwoot_user_id']).to eq(agent.id)
      expect(body['membership_created']).to be(true)
      expect(body['role']).to eq('agent')
    end
  end

  describe 'log filtering' do
    it 'filters password from logs' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      expect(filter.filter({ 'password' => 'secret', 'email' => 'a@b.c' }))
        .to eq({ 'password' => '[FILTERED]', 'email' => 'a@b.c' })
    end
  end
end
