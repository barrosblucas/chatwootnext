class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    look_up_exising_conversation || create_new_conversation
  end

  private

  def look_up_exising_conversation
    return unless @contact_inbox.inbox.lock_to_single_conversation?

    @contact_inbox.inbox.conversations.where(contact_id: @contact_inbox.contact_id).last
  end

  def create_new_conversation
    ::Conversation.create!(conversation_params)
  end

  def conversation_params
    additional_attributes = params[:additional_attributes]&.permit! || {}
    custom_attributes = params[:custom_attributes]&.permit! || {}
    status = params[:status].present? ? { status: params[:status] } : {}

    # TODO: temporary fallback for the old bot status in conversation, we will remove after couple of releases
    # commenting this out to see if there are any errors, if not we can remove this in subsequent releases
    # status = { status: 'pending' } if status[:status] == 'bot'
    {
      account_id: @contact_inbox.inbox.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: connecta_scoped_assignee_id(params[:assignee_id]),
      team_id: params[:team_id]
    }.merge(status)
  end

  # Scoped inboxes: a new conversation lands in the reception unit, so an
  # assignee without `atender` covering it is stripped (denial style: ignore,
  # do not raise — creation must not fail). Unresolvable reception unit or
  # unmarked inbox keeps the native value.
  def connecta_scoped_assignee_id(assignee_id)
    return assignee_id if assignee_id.blank?
    return assignee_id unless connecta_scope_enforced?

    unit = connecta_reception_unit
    return assignee_id if unit.nil?

    eligible = Connecta::Scope::AssignmentPolicy.target_eligible?(
      account: @contact_inbox.inbox.account, org_unit: unit, target_id: assignee_id
    )
    Rails.logger.warn("connecta_assign_skip inbox_id=#{@contact_inbox.inbox_id} target_id=#{assignee_id}") unless eligible
    eligible ? assignee_id : nil
  end

  def connecta_scope_enforced?
    Connecta::Scope::ScopedInbox.table_exists? && Connecta::Scope::Projection.marked?(@contact_inbox.inbox_id)
  rescue StandardError
    false
  end

  def connecta_reception_unit
    unit_id = ENV.fetch('CONNECTA_RECEPTION_ORG_UNIT_ID', '').to_s
    return nil if unit_id.blank?

    Connecta::Scope::OrgUnit.find_by(id: unit_id, enabled: true)
  end
end
