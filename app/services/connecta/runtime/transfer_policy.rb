class Connecta::Runtime::TransferPolicy
  def initialize(conversation:, actor:)
    @conversation = conversation
    @actor = actor
  end

  def authorize!
    ensure_feature_enabled!
    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: @conversation.id)
    ensure_inbox_ready!
    ensure_scope_active!(scope)
    ensure_transfer_permission!(scope)
    scope
  rescue ActiveRecord::RecordNotFound
    raise error('Conversation scope is unavailable', :not_found)
  end

  private

  def error(message, status)
    Connecta::Runtime::TransferTransaction::Error.new(message, status: status)
  end

  def ensure_feature_enabled!
    return if Connecta::Runtime::Feature.enabled?

    raise error('Connecta human-number is disabled', :forbidden)
  end

  def ensure_inbox_ready!
    inbox = Connecta::Scope::ScopedInbox.find_by(inbox_id: @conversation.inbox_id)
    raise error('Conversation is not in the human-number inbox', :forbidden) unless inbox&.enforcement == 'enforce'
    raise error('Human-number inbox is in maintenance', :conflict) if inbox.maintenance
  end

  def ensure_scope_active!(scope)
    return if scope.state == 'active' && scope.case_version.positive?

    raise error('Conversation is not active', :conflict)
  end

  def ensure_transfer_permission!(scope)
    # Administrador nativo same-account transfere entre quaisquer setores válidos
    # da própria conta, sem grant setorial. Conta do recurso validada no Gate do
    # endpoint; destino same-account validado na transação (build_local_transaction).
    return if Connecta::Scope::NativeAdmin.authorized_for?(@actor, @conversation)

    projection = Connecta::Scope::Projection.new(@actor)
    raise error('ACL projection is stale or user is revoked', :forbidden) unless projection.verified? && projection.fresh?

    can_transfer = projection.granted_paths(['transferir']).any? { |path| scope.org_unit.path.start_with?(path) }
    raise error('Transfer permission required for current unit', :forbidden) unless can_transfer
  end
end
