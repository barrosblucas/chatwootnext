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

    # Texto da pesquisa para conversa escopada (sem o link; o presenter anexa).
    def survey_message(conversation)
      template = conversation.inbox.csat_config&.dig('message').presence || DEFAULT_MESSAGE_TEMPLATE
      protocol = protocol_for(conversation).to_s
      template.gsub('{{protocolo}}', protocol).gsub('{{protocol}}', protocol)
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
  end
end
