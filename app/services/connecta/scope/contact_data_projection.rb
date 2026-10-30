# Projeção do DTO de contato para usuário só escopado (spike G0, RF2).
# Helper puro: oculta notas e atributos globais do contato em respostas, sem tocar modelo, banco, notas ou getters.
# Aplica-se SOMENTE ao DTO de contato; não varre Conversation/protocolo.
module Connecta::Scope::ContactDataProjection
  module_function

  def redact_contact(payload)
    copy = payload.to_h.dup
    copy.delete('custom_attributes')
    copy.delete(:custom_attributes)
    copy.delete('notes')
    copy.delete(:notes)
    copy
  end

  # Sanitize only contact DTOs in a socket payload. The listener job reloads conversation
  # payloads before broadcasting, so this projection runs after that reload as well.
  def socket_payload(payload, force_contact: false)
    copy = copy_socket_value(payload) do |contact_data|
      contact_id = contact_data['id'] || contact_data[:id]
      next contact_data unless socket_contact_restricted?(contact_id)

      redact_contact(contact_data)
    end
    force_contact && contact_dto?(copy) ? redact_contact(copy) : copy
  end

  # Contato vinculado + usuário sem admin nominal: só escopado. Usa Projection#admin? real, sem autorização nova.
  def restricted_contact?(contact, user)
    return false unless Connecta::Scope::ContactVisibility.linked?(contact)

    user.nil? || !Connecta::Scope::Projection.new(user).admin?
  end

  def copy_socket_value(value, &)
    case value
    when Hash
      copy = value.transform_values do |entry|
        copy_socket_value(entry, &)
      end
      copy = yield(copy) if contact_dto?(copy)
      copy
    when Array
      value.map { |entry| copy_socket_value(entry, &) }
    else
      value
    end
  end

  def contact_dto?(value)
    value.is_a?(Hash) && (value['type'] == 'contact' || value[:type] == 'contact')
  end

  def socket_contact_restricted?(contact_id)
    return false if contact_id.blank?

    contact = ::Contact.find_by(id: contact_id)
    contact && Connecta::Scope::ContactVisibility.linked?(contact)
  end

  # Texto para ferramentas Copilot (spike G0, RF2): sem restricao segue nativo;
  # restrito traz Contact ID + campos publicos nativos, sem notas globais nem custom attributes.
  # Contrato nativo lido: app/services/llm_formatter/contact_llm_formatter.rb:20.
  # Sem regex sobre texto, sem tocar core/model/getters, sem apagar/mudar dados.
  def llm_text(contact, user)
    return contact.to_llm_text unless restricted_contact?(contact, user)

    [
      "Contact ID: ##{contact.id}",
      'Contact Attributes:',
      "Name: #{contact.name}",
      "Email: #{contact.email}",
      "Phone: #{contact.phone_number}",
      "Location: #{contact.location}",
      "Country Code: #{contact.country_code}"
    ].join("\n")
  end
end
