require 'rails_helper'

# Fase 2 · modo da pesquisa por inbox (painel do município → fork via HMAC).
# Contrato de fio v1 em app/controllers/connecta/v1/csat_config_controller.rb.
RSpec.describe 'Connecta v1 CSAT config', type: :request do
  let(:secret) { 'test-platform-to-fork-secret' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:path) { '/connecta/v1/csat_config' }

  def signed_headers(timestamp, request_path, request_body)
    canonical = [timestamp, 'POST', request_path, request_body].join('.')
    {
      'X-Connecta-Timestamp' => timestamp,
      'X-Connecta-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)}",
      'Content-Type' => 'application/json'
    }
  end

  def post_signed(body_hash, at: Time.current)
    body = body_hash.to_json
    post path, params: body, headers: signed_headers(at.to_i.to_s, path, body)
  end

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'CONNECTA_ACCOUNT_ID' => account.id.to_s,
                        'CONNECTA_PLATFORM_TO_FORK_SECRET' => secret
                      ))
    Connecta::ScopedInbox.create!(inbox_id: inbox.id)
  end

  it 'aplica o modo whatsapp com janela e habilita a pesquisa' do
    post_signed({ account_id: account.id, inbox_id: inbox.id, mode: 'whatsapp', window_minutes: 30 })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'inbox_id' => inbox.id, 'mode' => 'whatsapp', 'window_minutes' => 30,
      'csat_survey_enabled' => true, 'display_type' => 'star', 'disable_feedback' => true
    )
    inbox.reload
    expect(inbox.csat_survey_enabled).to be(true)
    expect(inbox.csat_config).to include('mode' => 'whatsapp', 'window_minutes' => 30,
                                         'display_type' => 'star', 'disable_feedback' => true)
  end

  it 'é idempotente: repetir o mesmo corpo devolve a mesma config' do
    body = { account_id: account.id, inbox_id: inbox.id, mode: 'link', window_minutes: 45 }

    post_signed(body)
    first = response.parsed_body
    post_signed(body)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first)
  end

  it 'modo off desabilita a pesquisa' do
    post_signed({ account_id: account.id, inbox_id: inbox.id, mode: 'off' })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('mode' => 'off', 'csat_survey_enabled' => false)
    expect(inbox.reload.csat_survey_enabled).to be(false)
  end

  it 'usa 60 minutos quando a janela não vem' do
    post_signed({ account_id: account.id, inbox_id: inbox.id, mode: 'link' })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('window_minutes' => 60)
  end

  it 'recusa modo inválido com 422' do
    post_signed({ account_id: account.id, inbox_id: inbox.id, mode: 'sms', window_minutes: 10 })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('invalid_mode')
  end

  it 'recusa janela inválida com 422' do
    post_signed({ account_id: account.id, inbox_id: inbox.id, mode: 'link', window_minutes: 0 })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('invalid_window_minutes')
  end

  it 'devolve 404 para inbox fora do enforcement' do
    other = create(:inbox, account: account)

    post_signed({ account_id: account.id, inbox_id: other.id, mode: 'link', window_minutes: 10 })

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('inbox_not_enforced')
  end

  it 'recusa assinatura inválida com 401' do
    body = { account_id: account.id, inbox_id: inbox.id, mode: 'link' }.to_json
    headers = { 'X-Connecta-Timestamp' => Time.current.to_i.to_s,
                'X-Connecta-Signature' => 'sha256=0' * 8, 'Content-Type' => 'application/json' }
    post path, params: body, headers: headers

    expect(response).to have_http_status(:unauthorized)
  end
end
