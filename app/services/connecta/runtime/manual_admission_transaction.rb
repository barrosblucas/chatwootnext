# Admissão manual de conversa em inbox marcada (micro passo 3).
# Percurso completo UMA VEZ: cria a conversa SEM mensagem → admite/ativa no WP
# (autoridade verdadeira, HMAC assinado, fora de transação SQL) → só então envia
# a primeira mensagem via MessageBuilder com autorização de escrita + dispatch
# guard original. Actor e account sempre do servidor (Current), nunca do browser.
# Reuso autorizado nunca re-admite outro setor; transferência em progresso não
# permite envio inicial. Retry da mesma authority é idempotente (WP retorna
# reused/active sem novo caso).
class Connecta::Runtime::ManualAdmissionTransaction
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: :unprocessable_entity)
      @status = status
      super(message)
    end
  end

  IDEMPOTENCY_KEY_PATTERN = /\A[A-Za-z0-9._:-]{1,128}\z/

  def initialize(account_id:, contact_inbox:, actor:, org_unit_id:, message_params:, idempotency_key: nil) # rubocop:disable Metrics/ParameterLists
    @account_id = Integer(account_id)
    @contact_inbox = contact_inbox
    @actor = actor
    @org_unit_id = org_unit_id.to_s
    @message_params = message_params
    @idempotency_key = normalized_idempotency_key(idempotency_key)
    @client = Connecta::Runtime::PlatformClient.new
  rescue ArgumentError
    raise Error.new('account_id is invalid', status: :service_unavailable)
  end

  # Falhas 4xx do WP são definitivas: nenhuma admissão foi reservada, então a
  # conversa recém-criada (sem mensagem) não pode ficar na recepção. Timeout/5xx
  # seguem recuperáveis e preservam o rascunho para retry da mesma authority.
  DEFINITIVE_ADMISSION_FAILURES = %i[forbidden not_found conflict unprocessable_entity].freeze

  def call
    ensure_marked!
    ensure_org_unit!
    conversation, reused = find_or_create_conversation!
    begin
      admission = admit_in_wp!(conversation)
    rescue Error => e
      discard_unadmitted_conversation!(conversation) if !reused && DEFINITIVE_ADMISSION_FAILURES.include?(e.status)
      raise
    end
    scope = activate_scope!(conversation, admission)
    message = send_first_message!(conversation, scope) if @message_params.present?
    { conversation: conversation, scope: scope, message: message, reused: reused || admission['reused'] }
  rescue Connecta::Scope::Denied => e
    raise Error.new(e.message, status: e.status)
  end

  private

  def ensure_marked!
    return if Connecta::Scope::Projection.marked?(@contact_inbox.inbox_id)

    raise Error.new('Conversation is not in the human-number inbox', status: :forbidden)
  end

  def ensure_org_unit!
    raise Error.new('org_unit_id is required', status: :unprocessable_entity) if @org_unit_id.blank?
    raise Error.new('org_unit_id is invalid', status: :unprocessable_entity) unless uuid_format?(@org_unit_id)
  end

  def normalized_idempotency_key(value)
    key = value.to_s.strip
    return nil if key.empty?

    raise Error.new('idempotency_key is invalid', status: :unprocessable_entity) unless key.match?(IDEMPOTENCY_KEY_PATTERN)

    key
  end

  def uuid_format?(value)
    value.match?(/\A[0-9a-f-]{36}\z/i)
  end

  # Lock do par + reuso autorizado ou criação SEM mensagem (o after_create do
  # runtime registra o escopo reception). A transação é real: pg_advisory_xact_lock
  # só vale até o commit, então find/create + resolve precisam estar dentro dela.
  # O WP (HTTP externo) fica FORA do lock para não segurar a conexão.
  # Bypass de phone do ContactInboxBuilder (validate_baileys_phone: false):
  # contato WhatsApp sem cadastro é válido (AC2); a normalização on_whatsapp
  # (rede bloqueada em teste G0) NÃO pode quebrar a criação — o source_id
  # explícito do browser já é o identificador roteável.
  def find_or_create_conversation!
    ActiveRecord::Base.transaction do
      Connecta::Scope::ConversationReuse.lock!(inbox_id: @contact_inbox.inbox_id, contact_id: @contact_inbox.contact_id)
      existing = Connecta::Scope::ConversationReuse.resolve(user: @actor, inbox: @contact_inbox.inbox,
                                                            contact: @contact_inbox.contact)
      next [existing, true] unless existing.nil?

      conversation = ConversationBuilder.new(params: ActionController::Parameters.new,
                                             contact_inbox: @contact_inbox).perform
      [conversation, false]
    end
  rescue ActiveRecord::RecordNotUnique
    # Colisão real de duas criações do mesmo par: sob o lock, a segunda deve ver
    # a conversa commitada pela primeira. Se o índice ainda disparar (processo
    # externo criou entre o resolve e o insert), recupera o vencedor autorizado.
    existing = Connecta::Scope::ConversationReuse.resolve(user: @actor, inbox: @contact_inbox.inbox,
                                                          contact: @contact_inbox.contact)
    raise if existing.nil?

    [existing, true]
  end

  # Remoção compensatória só da conversa criada por esta admissão. O escopo
  # reception do after_create é apagado antes para não deixar órfão. Nunca
  # toca em conversa reutilizada (tem histórico/atendimento de outro ator).
  def discard_unadmitted_conversation!(conversation)
    ActiveRecord::Base.transaction do
      Connecta::Scope::ConversationScope.where(conversation_id: conversation.id).delete_all
      conversation.destroy!
    end
  rescue StandardError => e
    Rails.logger.error(
      "Connecta manual admission could not discard conversation #{conversation.id}: #{e.class}: #{e.message}"
    )
  end

  # WP fora de transação SQL: admite (caso/sessão verdadeiros) e ativa o scope.
  # Erros 4xx viram falha definitiva; timeout/5xx viram 503 recuperável (draft
  # preservado no browser, retry mesma conversa).
  def admit_in_wp!(conversation)
    payload = {
      account_id: @account_id, conversation_id: conversation.display_id,
      actor_chatwoot_user_id: @actor.id, org_unit_id: @org_unit_id
    }
    response = @client.post('/attendance/v1/manual-admissions', payload)
    raise Error.new("WP admission failed: #{response.inspect}", status: :bad_gateway) unless response.is_a?(Hash)

    response
  rescue Connecta::Runtime::PlatformClient::Error => e
    raise Error.new(e.message, status: e.status)
  end

  def activate_scope!(conversation, admission) # rubocop:disable Metrics/AbcSize
    expected = admission['case_protocol'].to_s
    version = Integer(admission['case_version'])
    Connecta::Scope::ConversationScope.transaction do
      scope = Connecta::Scope::ConversationScope.lock.find_by!(conversation_id: conversation.id)
      # Idempotência: já active com mesmo protocolo/versão/unidade → retorna.
      next scope if scope.state == 'active' && scope.case_protocol == expected &&
                    scope.case_version == version && scope.org_unit_id.to_s == @org_unit_id

      # transferring/pending nunca ativam por este caminho (só transferência real).
      if %w[transferring pending_activation activation_stuck].include?(scope.state)
        raise Error.new('Conversation is in transfer; sending is not allowed', status: :conflict)
      end

      scope.update!(
        org_unit_id: @org_unit_id, state: 'active', case_protocol: expected,
        platform_session_ref: admission['session_ref'].to_s, case_version: version, activated_at: Time.current
      )
      scope
    end
  rescue ActiveRecord::RecordNotFound
    raise Error.new('Conversation scope is unavailable', status: :not_found)
  rescue ArgumentError
    raise Error.new('WP admission response is invalid', status: :bad_gateway)
  end

  # Primeira mensagem UMA VEZ: exige write? na conversa ativa; source_id
  # estável (nonce explícito do draft/attempt, escopado conta+conversa+ator)
  # dedupa double-click/retry sem nova linha. O lock da conversa serializa duas
  # requisições do mesmo par; nonces distintos geram duas mensagens distintas.
  def send_first_message!(conversation, _scope)
    gate = Connecta::Scope::Gate.new(@actor)
    raise Error.new('You are not authorized to do this action', status: :forbidden) unless gate.write?(conversation,
                                                                                                       access_path: 'manual_admission_message')

    conversation.with_lock do
      dedupe_key = first_message_dedupe_key(conversation)
      existing = conversation.messages.find_by(source_id: dedupe_key)
      next existing unless existing.nil?

      params_with_key = @message_params.merge(source_id: dedupe_key)
      Messages::MessageBuilder.new(@actor, conversation, params_with_key).perform
    end
  end

  def first_message_dedupe_key(conversation)
    nonce = @idempotency_key || 'first'
    "manual-admission:#{conversation.account_id}:#{conversation.id}:#{@actor.id}:#{nonce}"
  end
end
