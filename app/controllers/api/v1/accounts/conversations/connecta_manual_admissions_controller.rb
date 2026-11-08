class Api::V1::Accounts::Conversations::ConnectaManualAdmissionsController < Api::V1::Accounts::BaseController
  include HmacConcern
  # Collection no nível da conta (sem :conversation_id): o before_action
  # :conversation do BaseController não existe neste controller (definido só
  # nas ações membro) — nada a pular; a autorização é inbox show? + contact.
  # Destinos elegíveis do ator (unidades com grant ATENDER): delega ao WP,
  # que revalida vínculo + grants no servidor. Actor e account sempre do
  # servidor (Current), nunca do browser. Collection (sem conversation_id):
  # autoriza pela inbox do contexto (show?) quando informada.
  def destinations
    if params[:inbox_id].present?
      inbox = Current.account.inboxes.find(params[:inbox_id])
      authorize inbox, :show?
    end
    account_id = Current.account.id
    query = URI.encode_www_form(account_id: account_id, actor_chatwoot_user_id: current_user.id)
    response = Connecta::Runtime::PlatformClient.new.get("/attendance/v1/manual-admission-destinations?#{query}")
    render json: response
  rescue Connecta::Runtime::PlatformClient::Error => e
    render json: { error: e.message }, status: e.status
  end

  # Admissão manual: cria a conversa SEM mensagem (se ainda não existe/reutilizada),
  # admite/ativa no WP (autoridade verdadeira, HMAC) e só ENTÃO envia a primeira
  # mensagem via MessageBuilder com autorização de escrita + dispatch guard.
  # Idempotente por conversation: reuso autorizado nunca re-admite outro setor.
  # Rota aninhada em conversations (BaseController): `conversation` autoriza
  # show? da conversa quando há conversation_id; quando não há, usa contexto
  # inbox/contact (inbox show? nativa + contact da conta).
  def create
    authorize_conversation_context!
    result = Connecta::Runtime::ManualAdmissionTransaction.new(
      account_id: Current.account.id,
      contact_inbox: @contact_inbox,
      actor: current_user,
      org_unit_id: admission_params[:org_unit_id],
      message_params: message_payload,
      idempotency_key: idempotency_key
    ).call
    @conversation = result[:conversation]
    render 'api/v1/accounts/conversations/show', status: result[:reused] ? :ok : :created
  rescue Connecta::Runtime::ManualAdmissionTransaction::Error, Connecta::Runtime::PlatformClient::Error => e
    render json: { error: e.message }, status: e.status
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, HTTParty::Error
    render json: { error: I18n.t('errors.conversations.connecta_transfer.timeout') }, status: :gateway_timeout
  end

  private

  # Contexto mínimo autorizado: inbox show? + contact da conta (nativo) +
  # leitura do atendimento existente (Gate) quando houver. Nunca bypass.
  def authorize_conversation_context!
    inbox
    contact
    contact_inbox
  end

  def authorize_conversation_access!
    conversation
  end

  def inbox
    @inbox = Current.account.inboxes.find(manual_context_params[:inbox_id])
    authorize @inbox, :show?
  end

  def contact
    @contact = Current.account.contacts.find(manual_context_params[:contact_id])
  end

  def contact_inbox
    # Reuso resolve ANTES de exigir contact_inbox existente: se o par já tem
    # contact_inbox, reutiliza; senão o ContactInboxBuilder cria SEM validação
    # de telefone Baileys (contato WhatsApp sem cadastro é válido; a
    # normalização on_whatsapp exige rede e NÃO pode quebrar a criação — o
    # source_id explícito já é o identificador roteável).
    @contact_inbox = ::ContactInbox.find_by(inbox_id: @inbox.id, contact_id: @contact.id,
                                            source_id: manual_context_params[:source_id])
    if @contact_inbox.nil?
      # Contato WhatsApp sem phone_number é válido (AC2): o source_id explícito
      # do browser é o identificador roteável. Garante o phone derivado do
      # source SÓ em memória (sem salvar no contato — sem fabricar cadastro):
      # o builder então usa o source explícito sem exigir cadastro.
      source = manual_context_params[:source_id].presence
      if source && @contact.phone_number.blank?
        digits = source.to_s.gsub(/\D/, '')
        @contact.phone_number = "+#{digits}" if digits.match?(/\A[1-9]\d{7,14}\z/)
      end
      @contact_inbox = ContactInboxBuilder.new(contact: @contact, inbox: @inbox,
                                               source_id: source,
                                               hmac_verified: hmac_verified?,
                                               validate_whatsapp_phone: false).perform
    end
    raise ActiveRecord::RecordNotFound if @contact_inbox.nil?

    authorize @contact_inbox.inbox, :show?
  end

  def manual_context_params
    params.permit(:inbox_id, :contact_id, :source_id)
  end

  def admission_params
    params.permit(:org_unit_id)
  end

  # Nonce explícito e estável por tentativa. O browser não decide o tipo,
  # privacidade nem o autor: o serviço sempre cria outgoing público com
  # sender=actor do servidor.
  def idempotency_key
    key = params[:idempotency_key].to_s.strip
    return nil if key.empty?

    unless key.match?(Connecta::Runtime::ManualAdmissionTransaction::IDEMPOTENCY_KEY_PATTERN)
      raise Connecta::Runtime::ManualAdmissionTransaction::Error.new(
        'idempotency_key is invalid', status: :unprocessable_entity
      )
    end

    key
  end

  # Whitelist estrita da primeira mensagem. Anexos só entram como upload
  # multipart nativo (UploadedFile); signed IDs de outra conta são recusados
  # porque o blob não prova vínculo de conta neste endpoint. Campos de
  # autor/tipo/privacidade enviados pelo browser são descartados.
  def message_payload
    message = params[:message]
    return nil if message.blank?

    invalid_message! unless message.is_a?(ActionController::Parameters)

    # Anexos não passam pelo permit (UploadedFile não é escalar de strong
    # params); a whitelist é o próprio validador de tipo abaixo.
    attachments = normalized_attachments(message[:attachments])
    validate_attachments!(attachments)
    permitted = message.permit(
      :content, :is_voice_message, :is_recorded_audio, :transcode_audio,
      attachments_metadata: {}
    )
    return nil if permitted[:content].blank? && attachments.blank?

    payload = permitted.to_h.with_indifferent_access
    payload[:attachments] = attachments
    payload[:message_type] = 'outgoing'
    payload[:private] = false
    payload
  end

  def normalized_attachments(value)
    return [] if value.blank?

    value.is_a?(Array) ? value : [value]
  end

  def validate_attachments!(attachments)
    return if attachments.all? { |attachment| uploaded_file?(attachment) }

    raise Connecta::Runtime::ManualAdmissionTransaction::Error.new(
      'message attachments must be uploaded files', status: :unprocessable_entity
    )
  end

  def invalid_message!
    raise Connecta::Runtime::ManualAdmissionTransaction::Error.new(
      'message is invalid', status: :unprocessable_entity
    )
  end

  def uploaded_file?(attachment)
    attachment.respond_to?(:tempfile) &&
      attachment.respond_to?(:original_filename) &&
      attachment.respond_to?(:content_type)
  end
end
