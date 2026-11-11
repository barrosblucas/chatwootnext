# Atribui a conversa escopada ao primeiro operador humano que responde.
# Quando uma conversa de inbox marcada está sem responsável, a primeira
# mensagem pública de saída de um agente (User) com escrita liberada pelo
# Gate vira o assignee — sem round-robin (a inbox do número humano opera
# com `enable_auto_assignment` desligado no deploy).
# Só age com o runtime ligado e o hook instalado (Scope::Installer e
# Runtime::Installer); fora disso o fluxo nativo segue intocado.
# Bot/relay (content_attributes `connecta_bot`/`relay_origin == 'bot'`),
# ecos externos sem sender, mensagens privadas/atividade/template,
# automação/campanha e usuário de serviço da recepção nunca atribuem;
# assignee existente (humano ou bot) nunca é sobrescrito. A atribuição
# usa lock de linha + releitura, então ASSIGNEE_CHANGED/ActionCable e a
# atividade de atribuição disparam pelo caminho nativo. Falha nunca
# quebra a criação da mensagem (só log com ids, sem PII).
module Connecta::Scope::FirstAgentAssignment
  ACCESS_PATH = 'first_agent_assignment'.freeze

  def execute_after_create_commit_callbacks
    super
    assign_first_agent
  end

  private

  def assign_first_agent
    Connecta::Scope::FirstAgentAssignment.assign_from(self)
  rescue StandardError => e
    Rails.logger.warn(
      "connecta_first_agent_assignment_skip conversation_id=#{conversation_id} " \
      "message_id=#{id} error=#{e.class}"
    )
  end

  class << self
    def assign_from(message)
      sender = message.sender
      return unless Connecta::Runtime::Feature.enabled?
      return unless assignable_shape?(message)
      return unless sender.is_a?(User)
      return if bot_or_relay?(message)
      return if Connecta::Runtime::Feature.reception_sender_user_ids.include?(sender.id)
      return unless Connecta::Scope::Projection.marked?(message.inbox_id)

      conversation = message.conversation
      return if conversation.nil?
      return if conversation.assignee_id.present? || conversation.assignee_agent_bot_id.present?
      return unless Connecta::Scope::Gate.new(sender).write?(conversation, access_path: ACCESS_PATH)

      conversation.with_lock do
        conversation.reload
        if conversation.assignee_id.blank? && conversation.assignee_agent_bot_id.blank?
          conversation.update!(assignee: sender)
        end
      end
    end

    private

    def assignable_shape?(message)
      message.outgoing? && !message.private? && !message.activity? && !message.template? &&
        message.content_attributes['automation_rule_id'].blank? &&
        message.additional_attributes['campaign_id'].blank?
    end

    def bot_or_relay?(message)
      attrs = message.content_attributes || {}
      attrs['connecta_bot'] == true || attrs[:connecta_bot] == true ||
        attrs['relay_origin'] == 'bot' || attrs[:relay_origin] == 'bot'
    end
  end
end
