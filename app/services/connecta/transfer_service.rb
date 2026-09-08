class Connecta::TransferService
  class Error < StandardError
    attr_reader :status

    def initialize(message, status:)
      @status = status
      super(message)
    end
  end

  REQUEST_TIMEOUT = 10

  def initialize(account:, conversation:, agent:)
    @account = account
    @conversation = conversation
    @agent = agent
  end

  def destinations
    ensure_configured!

    response = HTTParty.get(
      "#{gateway_url}/chatwoot/transfer/destinations",
      query: {
        from_inbox_id: @conversation.inbox_id,
        account_id: @account.id
      },
      headers: authorization_headers,
      timeout: REQUEST_TIMEOUT
    )

    handle_response(response)
  end

  def transfer(target_department_id:)
    ensure_configured!

    response = HTTParty.post(
      "#{gateway_url}/chatwoot/transfer",
      headers: authorization_headers.merge('Content-Type' => 'application/json'),
      body: {
        transfer_id: SecureRandom.uuid,
        account_id: @account.id,
        source_conversation_id: @conversation.display_id,
        target_department_id: target_department_id,
        agent: { id: @agent.id, email: @agent.email }
      }.to_json,
      timeout: REQUEST_TIMEOUT
    )

    handle_response(response)
  end

  private

  def ensure_configured!
    raise Error.new(I18n.t('errors.conversations.connecta_transfer.disabled'), status: :forbidden) unless transfer_enabled?

    return unless gateway_url.blank? || transfer_secret.blank?

    raise Error.new(I18n.t('errors.conversations.connecta_transfer.misconfigured'), status: :service_unavailable)
  end

  def transfer_enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('CONNECTA_TRANSFER_ENABLED', false))
  end

  def gateway_url
    account_url = @account.custom_attributes&.dig('connecta_gateway_url')
    return account_url.to_s.chomp('/') if account_url.present?

    GlobalConfigService.load("CONNECTA_GATEWAY_URL_#{@account.id}", nil).presence&.to_s&.chomp('/') ||
      GlobalConfigService.load('CONNECTA_GATEWAY_URL', nil).to_s.chomp('/')
  end

  def transfer_secret
    GlobalConfigService.load('CONNECTA_TRANSFER_SECRET', nil)
  end

  def authorization_headers
    { 'Authorization' => "Bearer #{transfer_secret}" }
  end

  def handle_response(response)
    case response.code
    when 200, 201
      response.parsed_response
    when 400
      raise Error.new(error_message(response), status: :unprocessable_entity)
    when 404
      raise Error.new(error_message(response), status: :not_found)
    when 409
      raise Error.new(error_message(response), status: :conflict)
    else
      raise Error.new(error_message(response), status: :bad_gateway)
    end
  end

  def error_message(response)
    parsed = response.parsed_response
    return parsed['error'] if parsed.is_a?(Hash) && parsed['error'].present?

    I18n.t('errors.conversations.connecta_transfer.gateway_error')
  end
end
