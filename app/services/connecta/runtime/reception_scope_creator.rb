class Connecta::Runtime::ReceptionScopeCreator
  class MissingReceptionUnit < StandardError; end

  # Contrato de fio v1: ingresso da recepção pelo webhook de conta Chatwoot (sem
  # /attendance/v1/agent-bot). Fail-closed explícito: sem unidade de recepção
  # configurada, a criação é recusada com erro de configuração (boot valida quando
  # a inbox está marcada) em vez de só logar e omitir o escopo.
  def self.call(conversation)
    inbox = Connecta::Scope::ScopedInbox.find_by(inbox_id: conversation.inbox_id)
    return unless inbox

    unit_id = ENV['CONNECTA_RECEPTION_ORG_UNIT_ID'].to_s
    unit = Connecta::Scope::OrgUnit.find_by(id: unit_id, enabled: true) if unit_id.present?
    unless unit
      raise MissingReceptionUnit,
            "Connecta reception scope missing: configure CONNECTA_RECEPTION_ORG_UNIT_ID for inbox_id=#{conversation.inbox_id}"
    end

    # NUNCA aposenta escopo de outra conversa: se o par (inbox, contato) já
    # tem atendimento não-terminal, o caminho de criação REUTILIZA o existente
    # (hook de reuso no controller, antes do ConversationBuilder) e este
    # callback só garante idempotência por conversation_id. O find_or_create
    # original continua válido quando não há colisão de par.
    existing = Connecta::Scope::ConversationScope.find_by(conversation_id: conversation.id)
    return existing if existing

    Connecta::Scope::ConversationScope.create!(
      conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
      org_unit: unit, state: 'reception', case_protocol: nil, case_version: 0
    )
  end

  def self.verify_marked_inboxes!
    marked = Connecta::Scope::ScopedInbox.where(enforcement: 'enforce')
    return if marked.empty?

    unit_id = ENV['CONNECTA_RECEPTION_ORG_UNIT_ID'].to_s
    unit = Connecta::Scope::OrgUnit.find_by(id: unit_id, enabled: true) if unit_id.present?
    return if unit

    raise MissingReceptionUnit,
          'Connecta reception unit is not configured (CONNECTA_RECEPTION_ORG_UNIT_ID) while a marked inbox exists'
  end
end
