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
    blobs.each do |blob|
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
    plan = inspect_plan

    expect(plan[:counts]).to include(
      conversations: 2, legacy_attachments: 2, conversation_scopes: 2
    )
    expect(plan[:counts][:messages]).to be >= messages.size
    result = apply_plan(plan)

    expect(result[:status]).to eq('committed')
    expect(result[:remaining_blob_ids]).to be_empty
    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(0)
    expect(Message.where(account_id: account.id).count).to eq(0)
    expect(Attachment.where(account_id: account.id).count).to eq(0)
    expect(Connecta::Scope::ConversationScope.where(inbox_id: inbox.id).count).to eq(0)
    expect(ActiveStorage::Blob.where(id: blobs.map(&:id)).count).to eq(0)
    expect(preserved_counts).to eq(before_counts)
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

    expect { apply_plan(plan) }.to raise_error(RuntimeError, 'probe')

    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(2)
    expect(Message.where(id: messages.map(&:id)).count).to eq(2)
    expect(Connecta::Scope::ConversationScope.where(conversation_id: conversations.map(&:id)).count).to eq(2)
    expect(Attachment.where(account_id: account.id).count).to eq(2)
    expect(ActiveStorage::Attachment.where(blob_id: blobs.map(&:id)).count).to eq(2)
    expect(ActiveStorage::Blob.where(id: blobs.map(&:id)).count).to eq(2)
    expect(preserved_counts).to eq(before_counts)
  end

  it 'purge de blob só ocorre após commit; falha transitória deixa pending e retry exato' do
    plan = inspect_plan
    failing_id = plan[:payload][:blob_ids].first
    first_attempt = true
    allow_any_instance_of(described_class).to receive(:purge_blob).and_wrap_original do |original, blob| # rubocop:disable RSpec/AnyInstance
      if blob.id == failing_id && first_attempt
        first_attempt = false
        raise IOError, 'transient storage error'
      end

      original.call(blob)
    end

    result = apply_plan(plan)

    expect(result[:status]).to eq('committed_blob_pending')
    expect(result[:remaining_blob_ids]).to eq([failing_id])
    expect(ActiveStorage::Blob.exists?(failing_id)).to be(true)
    expect(Conversation.where(id: conversations.map(&:id)).count).to eq(0)

    allow_any_instance_of(described_class).to receive(:purge_blob).and_call_original # rubocop:disable RSpec/AnyInstance
    retry_result = described_class.purge_blobs(blob_ids: result[:remaining_blob_ids])

    expect(retry_result[:status]).to eq('committed')
    expect(retry_result[:remaining_blob_ids]).to be_empty
    expect(ActiveStorage::Blob.exists?(failing_id)).to be(false)
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
