class BulkActionsJob < ApplicationJob
  include DateRangeHelper

  queue_as :medium
  attr_accessor :records

  MODEL_TYPE = ['Conversation'].freeze

  def perform(account:, params:, user:)
    @account = account
    @user = user
    Current.user = user
    @params = params
    @records = records_to_updated(params[:ids])
    bulk_update
  ensure
    Current.reset
  end

  def bulk_update
    bulk_remove_labels
    bulk_conversation_update
  end

  def bulk_conversation_update
    params = available_params(@params)
    records.each do |conversation|
      if connecta_marked?(conversation)
        conversation.with_lock do
          next unless connecta_bulk_allowed?(conversation, params)

          remove_labels(conversation)
          update_conversation(conversation, params)
        end
      else
        update_conversation(conversation, params)
      end
    rescue CustomExceptions::Conversation::AlreadyAssigned
      # The conversation belongs to another agent. Skip it instead of taking the
      # rest of the batch down with it: there is no response to raise into here.
      next
    end
  end

  def bulk_remove_labels
    records.each do |conversation|
      remove_labels(conversation) unless connecta_marked?(conversation)
    end
  end

  def connecta_marked?(conversation)
    Connecta::Scope::ScopedInbox.table_exists? && Connecta::Scope::Projection.marked?(conversation.inbox_id)
  end

  def connecta_bulk_allowed?(conversation, params)
    return false unless Connecta::Scope::Gate.new(@user).write?(conversation, access_path: 'bulk_job')
    return true unless params&.key?('assignee_id') || params&.key?(:assignee_id)

    Connecta::Scope::AssignmentPolicy.new(
      conversation: conversation, actor: @user,
      target_id: params[:assignee_id] || params['assignee_id'], target_type: nil
    ).allowed?
  end

  def update_conversation(conversation, params)
    bulk_add_labels(conversation)
    bulk_snoozed_until(conversation)
    conversation.update!(params) if params
  end

  def available_params(params)
    return unless params[:fields]

    params[:fields].delete_if { |key, value| value.nil? && key == 'status' }
  end

  def bulk_add_labels(conversation)
    conversation.add_labels(@params[:labels][:add]) if @params[:labels] && @params[:labels][:add]
  end

  def bulk_snoozed_until(conversation)
    conversation.snoozed_until = parse_date_time(@params[:snoozed_until].to_s) if @params[:snoozed_until]
  end

  def remove_labels(conversation)
    return unless @params[:labels] && @params[:labels][:remove]

    labels = conversation.label_list - @params[:labels][:remove]
    conversation.update!(label_list: labels)
  end

  def records_to_updated(ids)
    current_model = @params[:type].camelcase
    return unless MODEL_TYPE.include?(current_model)

    scope = current_model.constantize.where(account_id: @account.id, display_id: ids)
    Conversations::PermissionFilterService.new(scope, @user, @account).perform
  end
end
