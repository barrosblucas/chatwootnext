require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

Connecta::G0ScopeSchema.ensure!
Connecta::G0ProductTables.install!
Connecta::Transfer::Installer.install!

# Decisão 005 no caminho REAL de ingestão Baileys, com o runtime de produção
# instalado (callback after_create de recepção + after_update_commit de
# resolução). Sem transação externa: callbacks after_commit rodam de verdade.
# A limpeza remove só as linhas sintéticas deste exemplo.
RSpec.describe 'Connecta · inbound após conversa resolvida (Baileys real)', type: :request do
  self.use_transactional_tests = false

  let(:webhook_verify_token) { 'valid_token' }
  let(:run_id) { SecureRandom.hex(4) }
  let!(:account) { create(:account) }
  let!(:channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys',
                              provider_config: { webhook_verify_token: webhook_verify_token },
                              validate_provider_config: false, received_messages: false)
  end
  let!(:inbox) { channel.inbox.tap { |record| record.update!(lock_to_single_conversation: false, enable_auto_assignment: false) } }
  let!(:reception_unit) { Connecta::Scope::OrgUnit.create!(name: 'Recepção', path: "/recepcao-#{run_id}/") }

  before do
    stub_request(:get, /profile-picture-url/).to_return(status: 200, body: { data: { profilePictureUrl: nil } }.to_json)
    Connecta::Scope::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
    stub_const(
      'ENV',
      ENV.to_h.merge(
        'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
        'CONNECTA_RECEPTION_ORG_UNIT_ID' => reception_unit.id.to_s
      )
    )
    # Runtime de produção: instala o callback de recepção e o after_update_commit
    # de resolução. Se outro spec do processo já instalou, garante o callback
    # (ele é idempotente e checa Feature.enabled? em tempo de execução).
    Connecta::Runtime::Installer.install!
    unless Conversation._create_callbacks.any? do |callback|
      callback.filter.equal?(Connecta::Runtime::Installer::RECEPTION_CALLBACK)
    end
      Conversation.after_create(Connecta::Runtime::Installer::RECEPTION_CALLBACK)
    end
  end

  after do
    example_conversation_ids = Conversation.where(inbox: inbox).pluck(:id)
    Connecta::Transfer::OutboundDispatchRecord.where(conversation_id: example_conversation_ids).delete_all
    Connecta::Transfer::TransferRecord.where(
      'source_conversation_id IN (?) OR destination_conversation_id IN (?)',
      example_conversation_ids, example_conversation_ids
    ).delete_all
    Connecta::Scope::ConversationScope.where(inbox_id: inbox.id).delete_all
    Connecta::Scope::ScopedInbox.where(inbox_id: inbox.id).delete_all
    ContactInbox.where(inbox_id: inbox.id).delete_all
    Connecta::Scope::OrgUnit.where('path LIKE ?', "/recepcao-#{run_id}/%").delete_all

    connection = ActiveRecord::Base.connection
    account_tables = (connection.tables - ['accounts']).select { |table| connection.column_exists?(table, :account_id) }
    account_tables.each do |table|
      connection.delete("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
    end
    Account.where(id: account.id).delete_all

    leftovers = account_tables.to_h do |table|
      rows = connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
      [table, rows.to_i]
    end
    leftovers.merge!(
      accounts: Account.where(id: account.id).count,
      org_units_by_prefix: Connecta::Scope::OrgUnit.where('path LIKE ?', "/recepcao-#{run_id}/%").count,
      conversation_scopes_by_inbox: Connecta::Scope::ConversationScope.where(inbox_id: inbox.id).count,
      contact_inboxes_by_inbox: ContactInbox.where(inbox_id: inbox.id).count
    )
    Connecta::Runtime::Installer.uninstall_reception_callback!
    expect(leftovers.reject { |_table, count| count.zero? }).to eq({}) # rubocop:disable RSpec/ExpectInHook
  end

  def deliver(source_id, text)
    params = {
      webhookVerifyToken: webhook_verify_token,
      event: 'messages.upsert',
      data: {
        type: 'notify',
        messages: [{
          key: {
            id: source_id, remoteJid: '5511912345678@lid', remoteJidAlt: '5511912345678@s.whatsapp.net',
            fromMe: false, addressingMode: 'lid'
          },
          pushName: 'Cidadão Sintético',
          messageTimestamp: Time.current.to_i,
          message: { conversation: text }
        }]
      }
    }
    Whatsapp::IncomingMessageBaileysService.new(inbox: inbox, params: params).perform
  end

  # rubocop:disable RSpec/MultipleExpectations
  it 'cria conversa nova e preserva a anterior resolvida; retry antigo não duplica' do
    deliver('old-1', 'primeira mensagem')
    old_conversation = Conversation.find_by!(inbox: inbox)
    old_scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: old_conversation.id)
    expect(old_scope.state).to eq('reception')
    old_scope.update!(state: 'active', case_protocol: 'CASO-OLD', case_version: 1)

    deliver('old-2', 'segunda mensagem')
    old_conversation.reload
    old_message_ids = old_conversation.messages.order(:id).pluck(:id)
    expect(old_message_ids.size).to eq(2)

    old_conversation.update!(status: :resolved)
    expect(old_conversation.reload.status).to eq('resolved')
    expect(old_scope.reload.state).to eq('closed')
    expect(old_scope.closed_at).not_to be_nil
    expect(old_scope.case_protocol).to eq('CASO-OLD')
    expect(old_conversation.messages.order(:id).pluck(:id)).to eq(old_message_ids)

    expect do
      deliver('new-1', 'nova mensagem')
    end.to change(Conversation, :count).by(1)

    new_conversation = Conversation.where(inbox: inbox).where.not(id: old_conversation.id).sole
    new_scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: new_conversation.id)
    expect(new_conversation.inbox_id).to eq(old_conversation.inbox_id)
    expect(new_conversation.contact_id).to eq(old_conversation.contact_id)
    expect(new_conversation.contact_inbox.source_id).to eq(old_conversation.contact_inbox.source_id)
    expect(new_conversation.display_id).not_to eq(old_conversation.display_id)
    expect(new_scope.state).to eq('reception')
    expect(new_scope.case_protocol).to be_nil
    expect(new_scope.org_unit_id).to eq(reception_unit.id)
    expect(new_conversation.status).to eq('open')
    expect(new_conversation.messages.pluck(:content)).to contain_exactly('nova mensagem')
    expect(old_conversation.reload.messages.order(:id).pluck(:id)).to eq(old_message_ids)
    expect(old_conversation.status).to eq('resolved')

    expect do
      deliver('new-2', 'outra mensagem')
    end.not_to change(Conversation, :count)
    expect(new_conversation.reload.messages.order(:id).pluck(:content)).to contain_exactly('nova mensagem', 'outra mensagem')
    expect(old_conversation.reload.messages.order(:id).pluck(:id)).to eq(old_message_ids)

    expect do
      deliver('old-2', 'segunda mensagem')
    end.not_to change(Conversation, :count)
    expect(new_conversation.reload.messages.count).to eq(2)
    expect(old_conversation.reload.messages.order(:id).pluck(:id)).to eq(old_message_ids)
  end
  # rubocop:enable RSpec/MultipleExpectations

  it 'exige lock_to_single_conversation=false para o novo inbound não reutilizar a resolvida' do
    expect(inbox.reload.lock_to_single_conversation).to be(false)
  end
end
