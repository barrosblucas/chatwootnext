class Connecta::Runtime::PlatformClient
  REQUEST_TIMEOUT = 5

  class Error < StandardError
    attr_reader :status

    def initialize(message, status: :bad_gateway)
      @status = status
      super(message)
    end
  end

  def initialize(base_url: ENV.fetch('CONNECTA_PLATFORM_URL', nil), secret: ENV.fetch('CONNECTA_FORK_TO_PLATFORM_SECRET', nil))
    @base_url = base_url.to_s.chomp('/')
    @secret = secret.to_s
  end

  def get(path)
    request(:get, path)
  end

  def post(path, payload)
    request(:post, path, payload)
  end

  private

  def request(method, path, payload = nil)
    ensure_configured!
    body = payload.nil? ? '' : payload.to_json
    response = HTTParty.public_send(method, "#{@base_url}#{path}", headers: request_headers(method, path, body),
                                                                   body: body.presence, timeout: REQUEST_TIMEOUT)
    parsed = response.parsed_response
    return parsed if response.success?

    detail = parsed.is_a?(Hash) ? parsed['error'] : nil
    raise Error.new(detail.presence || 'Connecta platform request failed', status: http_status(response.code))
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, HTTParty::Error => e
    raise Error.new("Connecta platform unavailable: #{e.class}", status: :gateway_timeout)
  end

  def ensure_configured!
    return unless @base_url.blank? || @secret.blank?

    raise Error.new('Connecta platform client is not configured', status: :service_unavailable)
  end

  # Assinatura HMAC do contrato v1 (timestamp.METHOD.path.body). Gerada no momento do envio.
  def request_headers(method, path, body)
    timestamp = Time.current.to_i.to_s
    canonical = [timestamp, method.to_s.upcase, path, body].join('.')
    headers = {
      'X-Connecta-Timestamp' => timestamp,
      'X-Connecta-Signature' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, canonical)}",
      'Accept' => 'application/json'
    }
    headers['Content-Type'] = 'application/json' unless body.empty?
    headers
  end

  def http_status(code)
    case code
    when 401, 403 then :forbidden
    when 404 then :not_found
    when 409 then :conflict
    when 422 then :unprocessable_entity
    when 503 then :service_unavailable
    else :bad_gateway
    end
  end
end
