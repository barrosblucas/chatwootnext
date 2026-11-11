class Connecta::V1::ContactsController < Connecta::V1::BaseController
  # WP → fork (HMAC, Etapa 3): espelho do opt-out do bot por contato. Liga o
  # espelho local em contact.custom_attributes['connecta_bot_disabled']
  # (true = bot desligado; ausente = ligado) para o CSAT e os selos.
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: 'not_found' }, status: :not_found
  end

  def bot_optout
    contact_id = Integer(payload['contact_id'], exception: false)
    disabled = payload['disabled']
    unless contact_id.present? && (disabled == true || disabled == false)
      return render json: { error: 'invalid_params' }, status: :unprocessable_entity
    end

    contact = connecta_account.contacts.find(contact_id)
    attrs = contact.custom_attributes.is_a?(Hash) ? contact.custom_attributes.dup : {}
    if disabled
      attrs['connecta_bot_disabled'] = true
    else
      attrs.delete('connecta_bot_disabled')
    end
    contact.update!(custom_attributes: attrs)
    render json: { contact_id: contact.id, disabled: disabled }
  end

  private

  def connecta_account
    Account.find(Connecta::Runtime::Feature.current_account_id!)
  end
end
