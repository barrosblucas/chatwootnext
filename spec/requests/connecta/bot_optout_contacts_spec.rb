require 'rails_helper'

# Etapa 3 · WP → fork (HMAC): espelho do opt-out do bot por contato em
# contact.custom_attributes['connecta_bot_disabled'] (true = desligado;
# ausente = ligado). Contrato de fio v1: account_id conferido contra a conta
# configurada; 404 quando o contato não é da conta.
RSpec.describe 'Connecta v1 contacts bot opt-out', type: :request do
  let(:secret) { 'test-platform-to-fork-secret' }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def signed_headers(timestamp, request_path, request_body)
    canonical = ['POST', request_path, request_body].unshift(timestamp).join('.')
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
  end

  describe 'POST /connecta/v1/contacts/bot_optout' do
    let(:path) { '/connecta/v1/contacts/bot_optout' }

    it 'sets the flag on disable', :aggregate_failures do
      post_signed(path, { account_id: account.id, contact_id: contact.id, disabled: true })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ 'contact_id' => contact.id, 'disabled' => true })
      expect(contact.reload.custom_attributes['connecta_bot_disabled']).to be(true)
    end

    it 'removes the flag on re-enable and keeps other attributes', :aggregate_failures do
      contact.update!(custom_attributes: { 'connecta_bot_disabled' => true, 'other' => 'kept' })

      post_signed(path, { account_id: account.id, contact_id: contact.id, disabled: false })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ 'contact_id' => contact.id, 'disabled' => false })
      attrs = contact.reload.custom_attributes
      expect(attrs.key?('connecta_bot_disabled')).to be(false)
      expect(attrs['other']).to eq('kept')
    end

    it 'returns not found when the contact is not in the account' do
      other_contact = create(:contact)

      post_signed(path, { account_id: account.id, contact_id: other_contact.id, disabled: true })

      expect(response).to have_http_status(:not_found)
    end

    it 'returns unprocessable entity when disabled is missing' do
      post_signed(path, { account_id: account.id, contact_id: contact.id })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unprocessable entity when contact_id is missing' do
      post_signed(path, { account_id: account.id, disabled: true })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns unauthorized with a bad signature' do
      post path, params: { account_id: account.id, contact_id: contact.id, disabled: true }.to_json,
                 headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when account_id diverges from the configured account' do
      other_secret_account = create(:account)
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => other_secret_account.id.to_s,
                                       'CONNECTA_PLATFORM_TO_FORK_SECRET' => secret))

      post_signed(path, { account_id: account.id, contact_id: contact.id, disabled: true })

      expect(response).to have_http_status(:forbidden)
    end
  end
end
