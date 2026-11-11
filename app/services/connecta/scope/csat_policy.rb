# Regras do CSAT para conversas sob enforcement Connecta (Fase 2).
# Centraliza a leitura da projeção (inbox marcada + escopo com protocolo) para
# que o serviço de CSAT, os builders de mensagem e o push para o WP usem o
# mesmo critério. Modelos preferidos: os do domínio (`Scope::*`, que o
# G0Adapter aponta para as tabelas de produto em produção); fallback para os
# modelos de produto quando as tabelas G0 não existirem (testes comuns).
module Connecta::Scope::CsatPolicy
  # Texto padrão (pt-BR) quando a inbox não configurar `csat_config.message`.
  # A Fase 2 exige o protocolo na mensagem; a config pode trazer qualquer idioma
  # via `{{protocolo}}` (ou `{{protocol}}`).
  DEFAULT_MESSAGE_TEMPLATE = '✅ Seu atendimento do protocolo *{{protocolo}}* foi finalizado.\nAvalie o atendimento de 1 a 5:'.freeze

  # Texto padrão do modo whatsapp (sem link: o cidadão responde na conversa).
  WHATSAPP_MESSAGE_TEMPLATE = '✅ Seu atendimento do protocolo *{{protocolo}}* foi finalizado.\n' \
                              'Responda esta mensagem com uma nota de *1 a 5* para avaliar o atendimento ' \
                              '(1 = muito ruim, 5 = ótimo).'.freeze

  class << self
    # Inbox sob enforcement Connecta (alguma linha em connecta_scoped_inboxes).
    def scoped_inbox?(inbox_id)
      scoped_inbox_model&.exists?(inbox_id: inbox_id) || false
    end

    # Escopo Connecta da conversa, ou nil fora do enforcement/sem escopo.
    def scope_for(conversation)
      scope_model&.find_by(conversation_id: conversation.id)
    end

    # Protocolo do caso, ou nil quando a conversa não tem caso (só triagem).
    def protocol_for(conversation)
      scope_for(conversation)&.case_protocol.presence
    end

    # Resolução FINAL do protocolo: tem protocolo e não é origem de
    # transferência (a origem resolve via update_column e fica
    # `transferred_out`, sem evento e sem CSAT). Tolera a corrida com o hook de
    # resolução: o dispatcher do CSAT costuma rodar antes do
    # `after_update_commit` que fecha o escopo, então aceita qualquer estado
    # não-terminal com protocolo além do `closed`.
    def final_protocol_resolution?(conversation)
      scope = scope_for(conversation)
      return false if scope.nil? || scope.case_protocol.blank?

      scope.state != 'transferred_out'
    end

    # Flag genérica: esconde/desconsidera o comentário da pesquisa.
    def feedback_disabled?(inbox)
      inbox.csat_config.is_a?(Hash) && inbox.csat_config['disable_feedback'] == true
    end

    # Modo da pesquisa na inbox: "link" (padrão), "whatsapp" ou "off".
    def survey_mode(inbox)
      mode = inbox.csat_config.is_a?(Hash) ? inbox.csat_config['mode'].to_s : ''
      %w[whatsapp link off].include?(mode) ? mode : 'link'
    end

    def whatsapp_mode?(inbox)
      survey_mode(inbox) == 'whatsapp'
    end

    # Texto da pesquisa para conversa escopada. No modo whatsapp não há link
    # (o cidadão responde na conversa); no modo link o presenter anexa.
    def survey_message(conversation)
      return whatsapp_survey_message(conversation) if whatsapp_mode?(conversation.inbox)

      template = conversation.inbox.csat_config&.dig('message').presence || DEFAULT_MESSAGE_TEMPLATE
      protocol = protocol_for(conversation).to_s
      template.gsub('{{protocolo}}', protocol).gsub('{{protocol}}', protocol)
    end

    def whatsapp_survey_message(conversation)
      template = conversation.inbox.csat_config&.dig('message').presence || WHATSAPP_MESSAGE_TEMPLATE
      protocol = protocol_for(conversation).to_s
      template.gsub('{{protocolo}}', protocol).gsub('{{protocol}}', protocol)
    end

    # Conteúdo da mensagem de pesquisa para o builder nativo: conversa
    # escopada com protocolo usa o texto do protocolo (config com
    # `{{protocolo}}` ou padrão pt-BR); demais casos mantêm o nativo.
    def message_content_for(conversation)
      return survey_message(conversation) if scoped_inbox?(conversation.inbox_id) && protocol_for(conversation).present?

      conversation.inbox.csat_config&.dig('message') || 'Please rate this conversation'
    end

    # Opt-out do bot neste número (Etapa 3): espelho local em
    # contact.custom_attributes['connecta_bot_disabled']; bot desligado ⇒ sem
    # pesquisa automatizada, em qualquer inbox.
    def bot_disabled?(contact)
      return false if contact.nil?

      attrs = contact.custom_attributes
      attrs.is_a?(Hash) && attrs['connecta_bot_disabled'] == true
    end

    # Nomes das tabelas para SQL cru (claim): modelo do domínio quando a
    # tabela existe, senão o modelo de produto (runner comum sem G0Adapter).
    def scope_table_name
      pick_table_name(Connecta::Scope::ConversationScope, Connecta::ConversationScope)
    end

    def scoped_inbox_table_name
      pick_table_name(Connecta::Scope::ScopedInbox, Connecta::ScopedInbox)
    end

    private

    def scoped_inbox_model
      [Connecta::Scope::ScopedInbox, Connecta::ScopedInbox].find do |model|
        table_present?(model)
      end
    end

    def scope_model
      [Connecta::Scope::ConversationScope, Connecta::ConversationScope].find do |model|
        table_present?(model)
      end
    end

    def table_present?(model)
      model.table_exists?
    rescue StandardError
      false
    end

    def pick_table_name(primary, fallback)
      [primary, fallback].find { |model| table_present?(model) }&.table_name || primary.table_name
    end
  end
end
