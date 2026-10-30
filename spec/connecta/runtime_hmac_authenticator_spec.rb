require 'rails_helper'

RSpec.describe Connecta::Runtime::HmacAuthenticator do # rubocop:disable RSpec/SpecFilePathFormat -- layout plano de specs; renomear quebraria referências em evidências
  let(:secret) { 'test-connecta-direction-secret' }
  let(:path) { '/connecta/v1/acl/sync' }
  let(:body) { { projection_version: 4, events: [] }.to_json }

  def request_for(timestamp:, request_path: path, request_body: body)
    env = Rack::MockRequest.env_for(
      request_path, :method => 'POST', :input => request_body,
                    'HTTP_X_CONNECTA_TIMESTAMP' => timestamp,
                    'HTTP_X_CONNECTA_SIGNATURE' => signature_for(timestamp, request_path, request_body)
    )
    ActionDispatch::Request.new(env)
  end

  def signature_for(timestamp, request_path, request_body)
    canonical = [timestamp, 'POST', request_path, request_body].join('.')
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, canonical)}"
  end

  it 'verifies the timestamp, method, request target, and raw body together' do
    timestamp = Time.current.to_i.to_s

    expect(described_class.new(secret: secret).verify!(request_for(timestamp: timestamp))).to be(true)
  end

  it 'rejects a signature replayed on another endpoint' do
    timestamp = Time.current.to_i.to_s
    request = request_for(timestamp: timestamp, request_path: '/connecta/v1/acl/revoke')
    allow(request).to receive(:fullpath).and_return(path)

    expect { described_class.new(secret: secret).verify!(request) }
      .to raise_error(described_class::InvalidSignature, /mismatch/)
  end

  it 'rejects requests outside the replay window' do
    timestamp = (Time.current.to_i - described_class::WINDOW.to_i - 1).to_s

    expect { described_class.new(secret: secret).verify!(request_for(timestamp: timestamp)) }
      .to raise_error(described_class::InvalidSignature, /expired/)
  end
end
