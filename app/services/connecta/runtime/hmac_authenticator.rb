class Connecta::Runtime::HmacAuthenticator
  WINDOW = 60.seconds
  HEADER_TIMESTAMP = 'X-Connecta-Timestamp'.freeze
  HEADER_SIGNATURE = 'X-Connecta-Signature'.freeze

  class InvalidSignature < StandardError; end

  def initialize(secret:)
    @secret = secret.to_s
  end

  # Verificação HMAC em sequência fixa (formato, janela, assinatura); cada guard é um contrato v1.
  def verify!(request) # rubocop:disable Metrics/AbcSize
    raise InvalidSignature, 'Connecta HMAC secret is not configured' if @secret.blank?

    timestamp = request.headers[HEADER_TIMESTAMP].to_s
    signature = request.headers[HEADER_SIGNATURE].to_s
    raise InvalidSignature, 'Connecta timestamp is invalid' unless timestamp.match?(/\A\d{10}\z/)
    raise InvalidSignature, 'Connecta signature is invalid' unless signature.match?(/\Asha256=[0-9a-f]{64}\z/i)

    signed_at = Time.at(timestamp.to_i).utc
    raise InvalidSignature, 'Connecta request timestamp expired' if (Time.current - signed_at).abs > WINDOW

    raw_body = request.raw_post
    canonical = [timestamp, request.request_method.upcase, request.fullpath, raw_body].join('.')
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, canonical)}"
    valid = ActiveSupport::SecurityUtils.secure_compare(expected.downcase, signature.downcase)
    raise InvalidSignature, 'Connecta signature mismatch' unless valid

    true
  ensure
    request.body.rewind if request.body.respond_to?(:rewind)
  end
end
