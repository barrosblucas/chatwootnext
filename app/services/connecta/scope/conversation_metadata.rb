# Metadados de identificação da conversa para a lista (raiz, setor e protocolo).
# A lista já passou por ConversationQuery; este serviço só enriquece as linhas
# visíveis, em duas consultas (escopos + unidades), sem N+1 por conversa.
class Connecta::Scope::ConversationMetadata
  MAX_IDS = 50
  MAX_DEPTH = 20

  class << self
    def for_conversations(conversations)
      ids = Array(conversations).filter_map(&:id).uniq
      return {} if ids.empty?

      scopes = Connecta::Scope::ConversationScope
               .where(conversation_id: ids, inbox_id: Connecta::Scope::ScopedInbox.select(:inbox_id))
               .to_a
      return {} if scopes.empty?

      units = org_unit_map
      scopes.each_with_object({}) do |scope, result|
        result[scope.conversation_id] = payload(scope, units)
      end
    end

    def org_unit_map
      Connecta::Scope::OrgUnit.pluck(:id, :name, :parent_id).each_with_object({}) do |(id, name, parent_id), result|
        result[id] = { id: id, name: name, parent_id: parent_id }
      end
    end

    private

    def payload(scope, units)
      unit = units[scope.org_unit_id]
      {
        case_protocol: scope.case_protocol,
        state: scope.state,
        org_unit_name: unit&.fetch(:name, nil),
        root_unit_name: root_unit_name(unit, units)
      }
    end

    def root_unit_name(unit, units)
      current = unit
      depth = 0
      while current && current[:parent_id] && depth < MAX_DEPTH
        parent = units[current[:parent_id]]
        break if parent.nil? || parent[:id] == current[:id]

        current = parent
        depth += 1
      end
      current&.fetch(:name, nil)
    end
  end
end
