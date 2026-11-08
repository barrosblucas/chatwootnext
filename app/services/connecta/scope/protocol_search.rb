# Busca de conversas por protocolo municipal, sempre sobre uma relação já
# escopada por ConversationQuery/Gate. O join é feito apenas na tabela de
# escopos do Connecta; conversas fora de inbox marcada não têm escopo e não
# entram no resultado. O wildcard digitado é literal (sanitize_sql_like), para
# que "%" ou "_" não enumerem protocolos.
class Connecta::Scope::ProtocolSearch
  MAX_QUERY_LENGTH = 60
  PROTOCOL_PATTERN = /\A[A-Z0-9][A-Z0-9._-]{1,59}\z/

  class << self
    def apply(relation, query)
      normalized = normalize_query(query)
      return relation.none if normalized.nil?

      scope_table = Connecta::Scope::ConversationScope.quoted_table_name
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(normalized)}%"
      relation
        .joins("INNER JOIN #{scope_table} connecta_protocol_scopes " \
               'ON connecta_protocol_scopes.conversation_id = conversations.id')
        .where(conversations: { inbox_id: Connecta::Scope::ScopedInbox.select(:inbox_id) })
        .where('connecta_protocol_scopes.case_protocol ILIKE ?', pattern)
        .distinct
    end

    def normalize_query(value)
      normalized = normalize(value)
      normalized if normalized && normalized.length <= MAX_QUERY_LENGTH
    end

    def normalize_protocol(value)
      normalized = normalize(value)
      normalized if normalized&.match?(PROTOCOL_PATTERN)
    end

    private

    def normalize(value)
      normalized = value.to_s.strip.upcase
      return nil if normalized.empty?
      return nil if normalized.length > MAX_QUERY_LENGTH
      return nil if normalized.match?(/[\u0000-\u001f\u007f]/)

      normalized
    end
  end
end
