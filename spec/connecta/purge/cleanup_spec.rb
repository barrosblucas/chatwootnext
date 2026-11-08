require_relative '../../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative '../support/g0_scope_schema'

Connecta::G0ScopeSchema.ensure!

# Contrato interno de limpeza (sem rota HTTP): fixtures 100% sintéticas,
# transação real e ActiveStorage em storage de teste. Nada aqui aponta para
# conta/UUID/digest de produção.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Connecta::Purge::Cleanup do
  let(:run_id) { SecureRandom.hex(4) }
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, name: "Caixa purge #{run_id}") }
  let!(:org_unit) { Connecta::Scope::OrgUnit.create!(name: 'Setor sintético', path: "/purge-#{run_id}/") }
  let!(:conversations) do
    Array.new(2) do
      contact = create(:contact, account: account)
      create(:conversation, account: account, inbox: inbox, contact: contact)
    end
  end
  let!(:messages) do
    conversations.map do |conversation|
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       sender: conversation.contact, message_type: :incoming, content: 'sintético')
    end
  end
  let!(:blobs) do
    messages.map do |message|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('conteúdo sintético'),
        filename: "synthetic-#{run_id}-#{message.id}.txt",
        content_type: 'text/plain'
      )
      message.attachments.create!(account_id: account.id, file_type: :file, file: blob)
      blob
    end
  end
  let!(:scheduled_messages) do
    [
      create(:scheduled_message, account: account, inbox: inbox, conversation: conversations.first,
                                 author: create(:user, account: account)),
      create(:recurring_scheduled_message, account: account, inbox: inbox, conversation: conversations.last,
                                           author: create(:user, account: account))
    ]
  end
  let!(:scheduled_blobs) do
    scheduled_messages.map do |record|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('agendado sintético'),
        filename: "scheduled-#{run_id}-#{record.id}.txt",
        content_type: 'text/plain'
      )
      record.attachment.attach(blob)
      blob
    end
  end
  let(:extra_blobs) { [] }
  let(:account_ids) { [account.id] }

  before do
    create(:user, account: account, role: :agent)
    InstallationConfig.create!(name: "purge_test_#{run_id}", value: 'synthetic', locked: true)
    conversations.each do |conversation|
      Connecta::Scope::ConversationScope.create!(
        conversation_id: conversation.id, inbox_id: inbox.id, contact_id: conversation.contact_id,
        org_unit: org_unit, state: 'active', case_protocol: 'SYNTH-PURGE', case_version: 1
      )
    end
  end

  after do
    (blobs + scheduled_blobs + extra_blobs).each do |blob|
      ActiveStorage::Blob.service.delete(blob.key)
    rescue StandardError
      nil
    end
  end

  def inspect_plan
    described_class.plan(account_ids: account_ids)
  end

  def apply_plan(plan)
    described_class.apply(
      account_ids: account_ids,
      expected_hash: plan[:inventory_hash],
      confirmation: "APPLY:#{plan[:inventory_hash]}",
      writers_stopped: true
    )
  end

  def preserved_counts
    [Account, User, AccountUser, Inbox, Contact, ContactInbox, InstallationConfig,
     Connecta::Scope::OrgUnit, Team, Label, Webhook]
      .to_h { |model| [model.name, model.count] }
  end

  it 'remove conversas, mensagens e escopos, preservando contatos, caixas, contas, usuários e config' do
    before_counts = preserved_counts
    before_audits = [Audited::Audit.count, Connecta::Scope::AccessAudit.count]
    plan = inspect_plan

    expect(plan[:counts]).to include(
      conversations: 2, legacy_attachments: 2, conversation_scopes: 2,
      scheduled_messages: 1, recurring_scheduled_messages: 1, active_storage_attachments: 4
    )
    expect(plan[:counts][:messages]).to be >= messages.size
    result = apply_plan(plan)

    expect(result[:status]).to eq('committed')
    expect(result[:remaining_blob_ids]).to be_empty
    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(0)
    expect(Message.where(account_id: account.id).count).to eq(0)
    expect(Attachment.where(account_id: account.id).count).to eq(0)
    expect(ScheduledMessage.where(account_id: account.id).count).to eq(0)
    expect(RecurringScheduledMessage.where(account_id: account.id).count).to eq(0)
    expect(Connecta::Scope::ConversationScope.where(inbox_id: inbox.id).count).to eq(0)
    expect(ActiveStorage::Blob.where(id: (blobs + scheduled_blobs).map(&:id)).count).to eq(0)
    expect(preserved_counts).to eq(before_counts)
    expect(Audited::Audit.count).to be >= before_audits[0]
    expect(Connecta::Scope::AccessAudit.count).to be >= before_audits[1]
  end

  it 'recusa listas protegidas/auditadas reduzidas antes de qualquer delete' do
    expect do
      described_class.plan(account_ids: account_ids, protected_tables: ['accounts'])
    end.to raise_error(described_class::Blocked, 'PROTECTED_TABLES_IMMUTABLE')

    expect do
      described_class.plan(account_ids: account_ids, audit_tables: ['audits'])
    end.to raise_error(described_class::Blocked, 'AUDIT_TABLES_IMMUTABLE')
  end

  it 'aborta ANTES do commit quando um anexo novo entra depois do inventário' do
    plan = inspect_plan
    late_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('anexo tardio'), filename: "late-#{run_id}.txt", content_type: 'text/plain'
    )
    extra_blobs << late_blob
    messages.first.attachments.create!(account_id: account.id, file_type: :file, file: late_blob)

    expect { apply_plan(plan) }.to raise_error(described_class::Blocked, 'INVENTORY_CHANGED')

    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(2)
    expect(ActiveStorage::Blob.exists?(late_blob.id)).to be(true)
    expect(ActiveStorage::Attachment.exists?(blob_id: late_blob.id)).to be(true)
  end

  it 'aborta ANTES de deletar quando installation_config muda' do
    plan = inspect_plan
    InstallationConfig.create!(name: "purge_delta_#{run_id}", value: 'synthetic', locked: true)

    expect { apply_plan(plan) }.to raise_error(described_class::Blocked, 'INVENTORY_CHANGED')

    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(2)
    expect(Message.where(id: messages.map(&:id)).count).to eq(2)
  end

  it 'aborta ANTES de deletar quando surge conversa nova na conta' do
    plan = inspect_plan
    create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))

    expect { apply_plan(plan) }.to raise_error(described_class::Blocked, 'INVENTORY_CHANGED')

    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(2)
    expect(Message.where(id: messages.map(&:id)).count).to eq(2)
    expect(Connecta::Scope::ConversationScope.where(conversation_id: conversations.map(&:id)).count).to eq(2)
    expect(ActiveStorage::Blob.where(id: blobs.map(&:id)).count).to eq(2)
  end

  it 'aborta ANTES de deletar quando protected count muda (rowcount/hash delta)' do
    plan = inspect_plan
    create(:contact, account: account)

    expect { apply_plan(plan) }.to raise_error(described_class::Blocked, 'INVENTORY_CHANGED')

    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(2)
    expect(Message.where(id: messages.map(&:id)).count).to eq(2)
  end

  it 'rollback da transação preserva conversas, mensagens, escopos, attachment rows e blobs' do
    before_counts = preserved_counts
    plan = inspect_plan
    allow_any_instance_of(Message).to receive(:destroy!).and_raise(RuntimeError, 'probe') # rubocop:disable RSpec/AnyInstance
    queued_before = ActiveJob::Base.queue_adapter.enqueued_jobs.size

    expect { apply_plan(plan) }.to raise_error(RuntimeError, 'probe')

    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(queued_before)
    (blobs + scheduled_blobs).each do |blob|
      expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(true)
    end
    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(2)
    expect(Message.where(id: messages.map(&:id)).count).to eq(2)
    expect(Connecta::Scope::ConversationScope.where(conversation_id: conversations.map(&:id)).count).to eq(2)
    expect(Attachment.where(account_id: account.id).count).to eq(2)
    expect(ScheduledMessage.where(account_id: account.id).count).to eq(1)
    expect(RecurringScheduledMessage.where(account_id: account.id).count).to eq(1)
    expect(ActiveStorage::Attachment.where(blob_id: (blobs + scheduled_blobs).map(&:id)).count).to eq(4)
    expect(ActiveStorage::Blob.where(id: (blobs + scheduled_blobs).map(&:id)).count).to eq(4)
    expect(preserved_counts).to eq(before_counts)
  end

  it 'rollback depois de Conversation#destroy! não enfileira purge e preserva anexos agendados' do
    plan = inspect_plan
    destroyed_conversations = 0
    queued_before = ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == ActiveStorage::PurgeJob }
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Conversation).to receive(:destroy!).and_wrap_original do |original, *args|
      result = original.call(*args)
      destroyed_conversations += 1
      result
    end
    allow_any_instance_of(described_class).to receive(:verify_targets_gone!)
      .and_raise(RuntimeError, 'post destroy probe')
    # rubocop:enable RSpec/AnyInstance

    expect { apply_plan(plan) }.to raise_error(RuntimeError, 'post destroy probe')
    expect(destroyed_conversations).to eq(2)
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == ActiveStorage::PurgeJob })
      .to eq(queued_before)
    expect(ScheduledMessage.where(account_id: account.id).count).to eq(1)
    expect(RecurringScheduledMessage.where(account_id: account.id).count).to eq(1)
    expect(ActiveStorage::Attachment.where(blob_id: (blobs + scheduled_blobs).map(&:id)).count).to eq(4)
    expect(ActiveStorage::Blob.where(id: (blobs + scheduled_blobs).map(&:id)).count).to eq(4)
    (blobs + scheduled_blobs).each do |blob|
      expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(true)
    end

    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Conversation).to receive(:destroy!).and_call_original
    allow_any_instance_of(described_class).to receive(:verify_targets_gone!).and_call_original
    # rubocop:enable RSpec/AnyInstance
    result = apply_plan(plan)

    expect(result[:status]).to eq('committed')
    expect(ScheduledMessage.where(account_id: account.id).count).to eq(0)
    expect(RecurringScheduledMessage.where(account_id: account.id).count).to eq(0)
    expect(ActiveStorage::Attachment.where(blob_id: (blobs + scheduled_blobs).map(&:id)).count).to eq(0)
    expect(ActiveStorage::Blob.where(id: (blobs + scheduled_blobs).map(&:id)).count).to eq(0)
    (blobs + scheduled_blobs).each do |blob|
      expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(false)
    end
  end

  it 'falha real de service.delete deixa manifesto pending e retry exato mesmo com row ausente' do
    plan = inspect_plan
    failing = plan[:payload][:blobs].first
    first_attempt = true
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:delete).and_wrap_original do |original, key|
      if key == failing[:key] && first_attempt
        first_attempt = false
        raise IOError, 'transient storage error'
      end

      original.call(key)
    end
    # rubocop:enable RSpec/AnyInstance

    result = apply_plan(plan)

    expect(result[:status]).to eq('committed_blob_pending')
    expect(result[:remaining_blobs].map { |entry| entry[:key] }).to include(failing[:key])
    expect(ActiveStorage::Blob.exists?(failing[:id])).to be(true)
    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(0)

    # O retry não depende da row: simula row já ausente e usa o manifesto opaco.
    ActiveStorage::Blob.where(id: failing[:id]).delete_all
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:delete).and_call_original # rubocop:disable RSpec/AnyInstance
    retry_result = described_class.purge_blobs(blobs: result[:remaining_blobs])

    expect(retry_result[:status]).to eq('committed')
    expect(retry_result[:remaining_blobs]).to be_empty
    expect(ActiveStorage::Blob.exists?(failing[:id])).to be(false)
  end

  it 'arquivo ausente comprovado permite remover metadata e declarar commit' do
    plan = inspect_plan
    target = plan[:payload][:blobs].first
    target_blob = ActiveStorage::Blob.find(target[:id])
    ActiveStorage::Blob.service.delete(target_blob.key)

    result = apply_plan(plan)

    expect(result[:status]).to eq('committed')
    expect(ActiveStorage::Blob.exists?(target[:id])).to be(false)
  end

  it 'recusa apply sem writers parados ou confirmação/hash exatos' do
    plan = inspect_plan

    expect do
      described_class.apply(
        account_ids: account_ids, expected_hash: plan[:inventory_hash],
        confirmation: "APPLY:#{plan[:inventory_hash]}", writers_stopped: false
      )
    end.to raise_error(described_class::Blocked, 'WRITERS_NOT_STOPPED')

    expect do
      described_class.apply(
        account_ids: account_ids, expected_hash: plan[:inventory_hash],
        confirmation: 'APPLY:errado', writers_stopped: true
      )
    end.to raise_error(described_class::Blocked, 'CONFIRMATION_REQUIRED')
  end
end
# rubocop:enable RSpec/MultipleExpectations
