# Visão por protocolo: todas as etapas visíveis ao ator, na ordem cronológica.
# A consulta parte da conta e da inbox marcada; cada etapa passa pelo Gate, que
# audita allow/deny. Etapas ocultas não entram no payload (nem id, nem nome,
# nem link). Nenhum dado do cidadão é serializado.
class Connecta::Scope::ProtocolView
  class << self
    def call(account:, user:, protocol:)
      normalized = Connecta::Scope::ProtocolSearch.normalize_protocol(protocol)
      return nil if normalized.nil?

      conversations = visible_conversations(account, normalized)
      return nil if conversations.empty?

      visible = visible_scopes(conversations, normalized, user)
      return nil if visible.empty?

      serialize(normalized, visible, conversations)
    end

    private

    def visible_conversations(account, protocol)
      candidate_ids = Connecta::Scope::ConversationScope
                      .where(case_protocol: protocol)
                      .distinct
                      .pluck(:conversation_id)
      return {} if candidate_ids.empty?

      account.conversations
             .where(id: candidate_ids)
             .where(inbox_id: Connecta::Scope::ScopedInbox.select(:inbox_id))
             .includes(:assignee)
             .to_a
             .index_by(&:id)
    end

    def visible_scopes(conversations, protocol, user)
      gate = Connecta::Scope::Gate.new(user)
      scopes = Connecta::Scope::ConversationScope
               .where(conversation_id: conversations.keys, case_protocol: protocol)
               .includes(:org_unit)
               .order(:created_at, :id)
      scopes.select do |scope|
        conversation = conversations[scope.conversation_id]
        conversation && gate.read?(conversation, access_path: 'protocol_view')
      end
    end

    def serialize(protocol, visible, conversations)
      units = Connecta::Scope::ConversationMetadata.org_unit_map
      {
        protocol: protocol,
        stages: visible.map { |scope| stage_payload(scope, conversations[scope.conversation_id], units) }
      }
    end

    def stage_payload(scope, conversation, units)
      unit = units[scope.org_unit_id]
      {
        conversation_id: conversation.display_id,
        status: conversation.status,
        state: scope.state,
        root_unit_name: root_unit_name(unit, units),
        org_unit_name: unit&.fetch(:name, nil),
        assignee_name: assignee_name(conversation.assignee),
        started_at: scope.created_at&.iso8601,
        updated_at: scope.updated_at&.iso8601
      }
    end

    def assignee_name(assignee)
      return nil if assignee.nil?

      assignee.respond_to?(:available_name) ? assignee.available_name : assignee.name
    end

    def root_unit_name(unit, units)
      current = unit
      depth = 0
      while current && current[:parent_id] && depth < Connecta::Scope::ConversationMetadata::MAX_DEPTH
        parent = units[current[:parent_id]]
        break if parent.nil? || parent[:id] == current[:id]

        current = parent
        depth += 1
      end
      current&.fetch(:name, nil)
    end
  end
end
