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
      message_params: message_payload
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

  def message_payload
    message = params[:message]
    return nil if message.blank?

    message.is_a?(ActionController::Parameters) ? message.permit!.to_h : message
  end
end
