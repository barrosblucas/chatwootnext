# Visão por protocolo: todas as etapas visíveis ao ator, na ordem cronológica.
# A consulta parte da conta e da inbox marcada; cada etapa passa pelo Gate, que
# audita allow/deny. Etapas ocultas não entram no payload (nem id, nem nome,
# nem link). Nenhum dado do cidadão é serializado.
class Connecta::Scope::ProtocolView
  MAX_STAGES = 200

  class << self
    def call(account:, user:, protocol:)
      normalized = Connecta::Scope::ProtocolSearch.normalize_protocol(protocol)
      return nil if normalized.nil?

      conversations = visible_conversations(account, normalized)
      return nil if conversations.empty?

      visible, truncated = visible_scopes(conversations, normalized, user, account)
      return nil if visible.empty?

      # Devolve o valor armazenado (o writer pode ter gravado mixed case), não
      # a forma normalizada da busca.
      stored_protocol = visible.filter_map(&:case_protocol).first || normalized
      serialize(stored_protocol, visible, conversations, truncated)
    end

    private

    # A consulta começa pela conta e pela inbox marcada; nunca faz pluck global
    # de protocolo em ConversationScope (que leria ids de outras contas antes
    # do filtro). A comparação é case-insensitive e literal (sem ILIKE/wildcard
    # na visão por protocolo).
    def visible_conversations(account, protocol)
      scope_table = Connecta::Scope::ConversationScope.quoted_table_name
      account.conversations
             .joins("INNER JOIN #{scope_table} connecta_protocol_view_scopes " \
                    'ON connecta_protocol_view_scopes.conversation_id = conversations.id')
             .where("LOWER(connecta_protocol_view_scopes.case_protocol) = ?", protocol.downcase)
             .where(conversations: { inbox_id: Connecta::Scope::ScopedInbox.select(:inbox_id) })
             .includes(:assignee)
             .distinct
             .to_a
             .index_by(&:id)
    end

    def visible_scopes(conversations, protocol, user, account)
      native_admin = Connecta::Scope::NativeAdmin.administrator?(user, account)
      gate = Connecta::Scope::Gate.new(user)
      scopes = Connecta::Scope::ConversationScope
               .where(conversation_id: conversations.keys)
               .where('LOWER(case_protocol) = ?', protocol.downcase)
               .includes(:org_unit)
               .order(:created_at, :id)
               .limit(MAX_STAGES + 1)
               .to_a
      truncated = scopes.length > MAX_STAGES
      scopes = scopes.first(MAX_STAGES)
      visible = scopes.select do |scope|
        conversation = conversations[scope.conversation_id]
        next false unless conversation
        # Contrato do papel nominal: não enumera a etapa transferred_out. O
        # administrador NATIVO da conta continua vendo a cadeia inteira.
        next false if !native_admin && scope.state == 'transferred_out'

        gate.read?(conversation, access_path: 'protocol_view', scope: scope)
      end
      [visible, truncated]
    end

    def serialize(protocol, visible, conversations, truncated)
      units = Connecta::Scope::ConversationMetadata.org_unit_map
      {
        protocol: protocol,
        truncated: truncated,
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
