class Api::V1::Accounts::Conversations::ConnectaBotOptoutsController < Api::V1::Accounts::Conversations::BaseController
  # Opt-out do bot por número (Etapa 3): o WP é a autoridade (lê/altera lá) e o
  # fork espelha em contact.custom_attributes['connecta_bot_disabled'] para o
  # CSAT e os selos. Só vale para conversas de inboxes sob enforcement
  # Connecta (número humano); fora disso 404. Autorização: show? da conversa
  # (qualquer agente/admin com leitura). Nunca usa contact.blocked (derrubaria
  # o inbound).
  def show
    return render_not_scoped unless scoped_inbox?

    response = platform_client.get(bot_optout_path)
    render json: { disabled: response['disabled'] == true, contact_id: response['contact_id'] }
  rescue Connecta::Runtime::PlatformClient::Error => e
    render json: { error: friendly_error(e) }, status: friendly_status(e.status)
  end

  def create
    return render_not_scoped unless scoped_inbox?
    return render_invalid unless valid_optout_param?

    payload = {
      account_id: Current.account.id,
      conversation_id: @conversation.display_id,
      disabled: params[:disabled],
      actor_chatwoot_user_id: current_user.id
    }
    response = platform_client.post('/attendance/v1/bot-optout', payload)
    disabled = response['disabled'] == true
    mirror_contact_optout(disabled)
    render json: { disabled: disabled, contact_id: response['contact_id'] }, status: :ok
  rescue Connecta::Runtime::PlatformClient::Error => e
    render json: { error: friendly_error(e) }, status: friendly_status(e.status)
  end

  private

  def platform_client
    Connecta::Runtime::PlatformClient.new
  end

  def bot_optout_path
    query = URI.encode_www_form(account_id: Current.account.id, conversation_id: @conversation.display_id)
    "/attendance/v1/bot-optout?#{query}"
  end

  def scoped_inbox?
    Connecta::Scope::CsatPolicy.scoped_inbox?(@conversation.inbox_id)
  end

  def render_not_scoped
    render json: { error: I18n.t('errors.conversations.connecta_bot_optout.not_scoped') }, status: :not_found
  end

  def render_invalid
    render json: { error: I18n.t('errors.conversations.connecta_bot_optout.disabled_required') }, status: :unprocessable_entity
  end

  def valid_optout_param?
    params[:disabled] == true || params[:disabled] == false
  end

  def mirror_contact_optout(disabled)
    contact = @conversation.contact
    return if contact.nil?

    attrs = contact.custom_attributes.is_a?(Hash) ? contact.custom_attributes.dup : {}
    if disabled
      attrs['connecta_bot_disabled'] = true
    else
      attrs.delete('connecta_bot_disabled')
    end
    contact.update!(custom_attributes: attrs)
  end

  def friendly_error(error)
    return I18n.t('errors.conversations.connecta_bot_optout.not_human_service_inbox') if error.message == 'not_human_service_inbox'

    return I18n.t('errors.conversations.connecta_bot_optout.timeout') if upstream_unavailable?(error.status)

    error.message
  end

  def friendly_status(status)
    upstream_unavailable?(status) ? :service_unavailable : status
  end

  def upstream_unavailable?(status)
    [:bad_gateway, :gateway_timeout, :service_unavailable].include?(status)
  end
end
