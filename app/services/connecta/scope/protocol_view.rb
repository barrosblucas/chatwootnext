require 'base64'
require 'json'
require 'time'

# Visão por protocolo: etapas visíveis ao ator, em páginas cursor (created_at,id).
# A consulta é account-bound (conversations.account_id + inbox marcada), o Gate
# roda antes do corte da página e cada etapa visitada é auditada. O cursor é
# opaco e nunca enumera etapa oculta.
class Connecta::Scope::ProtocolView
  class InvalidRequest < StandardError; end

  DEFAULT_LIMIT = 50
  MAX_LIMIT = 100
  SCAN_BATCH_SIZE = 100
  CURSOR_VERSION = 1

  class << self
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def call(account:, user:, protocol:, cursor: nil, limit: nil)
      normalized = Connecta::Scope::ProtocolSearch.normalize_protocol(protocol)
      return nil if normalized.nil?

      page_size = normalize_limit(limit)
      position = decode_cursor(cursor)
      native_admin = Connecta::Scope::NativeAdmin.administrator?(user, account)
      gate = Connecta::Scope::Gate.new(user)
      visible = []
      next_position = nil

      loop do
        batch = scopes_batch(account, normalized, position)
        break if batch.empty?

        conversations = conversations_for(account, batch)
        # rubocop:disable Style/Next
        batch.each do |scope|
          conversation = conversations[scope.conversation_id]
          next unless conversation

          unless native_admin || scope.state != 'transferred_out'
            deny_nominal!(user, conversation)
            next
          end
          next unless gate.read?(conversation, access_path: 'protocol_view', scope: scope)

          visible << [scope, conversation]
          if visible.length >= page_size
            last_scope = batch.last
            next_position = [scope.created_at, scope.id] unless scope.equal?(last_scope) && batch.length < SCAN_BATCH_SIZE
            break
          end
        end
        # rubocop:enable Style/Next

        last = batch.last
        position = [last.created_at, last.id]
        break if visible.length >= page_size
        break if batch.length < SCAN_BATCH_SIZE
      end

      return nil if visible.empty?

      stored_protocol = visible.filter_map { |scope, _conversation| scope.case_protocol }.first || normalized
      units = Connecta::Scope::ConversationMetadata.org_unit_map
      {
        protocol: stored_protocol,
        native_admin: native_admin,
        stages: visible.map { |scope, conversation| stage_payload(scope, conversation, units) },
        next_cursor: next_position ? encode_cursor(*next_position) : nil
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    private

    def scopes_batch(account, protocol, position)
      table = Connecta::Scope::ConversationScope.quoted_table_name
      relation = Connecta::Scope::ConversationScope
                 .joins("INNER JOIN conversations ON conversations.id = #{table}.conversation_id")
                 .where(conversations: { account_id: account.id })
                 .where(conversations: { inbox_id: Connecta::Scope::ScopedInbox.select(:inbox_id) })
                 .where("LOWER(#{table}.case_protocol) = ?", protocol.downcase)
                 .includes(:org_unit)
                 .order("#{table}.created_at ASC, #{table}.id ASC")
                 .limit(SCAN_BATCH_SIZE)
      relation = relation.where("(#{table}.created_at, #{table}.id) > (?, ?)", position[0], position[1]) if position
      relation.to_a
    end

    def conversations_for(account, batch)
      Conversation.where(account_id: account.id, id: batch.map(&:conversation_id))
                  .includes(:assignee)
                  .index_by(&:id)
    end

    def deny_nominal!(user, conversation)
      Connecta::Scope::AccessAudit.create!(
        user_id: user.id, conversation_id: conversation.id, surface: 'conversation',
        access_path: 'protocol_view', decision: 'deny'
      )
    end

    def normalize_limit(value)
      return DEFAULT_LIMIT if value.blank?

      parsed = value.is_a?(Integer) ? value : Integer(value, 10)
      raise InvalidRequest, 'limit out of range' unless parsed.between?(1, MAX_LIMIT)

      parsed
    rescue ArgumentError, TypeError
      raise InvalidRequest, 'limit is invalid'
    end

    def encode_cursor(created_at, id)
      payload = { v: CURSOR_VERSION, at: created_at.iso8601(6), id: id }
      Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
    end

    def decode_cursor(value)
      return nil if value.blank?

      raw = Base64.urlsafe_decode64(value.to_s)
      data = JSON.parse(raw)
      raise InvalidRequest, 'cursor version' unless data['v'] == CURSOR_VERSION

      created_at = Time.iso8601(data['at'].to_s)
      id = Integer(data['id'], 10)
      raise InvalidRequest, 'cursor id' unless id.positive?

      [created_at, id]
    rescue ArgumentError, TypeError, JSON::ParserError, KeyError
      raise InvalidRequest, 'cursor is invalid'
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
