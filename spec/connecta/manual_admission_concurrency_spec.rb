require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

Connecta::G0ScopeSchema.ensure!
Connecta::G0ProductTables.install!
Connecta::Transfer::Installer.install!

# Concorrência REAL no Postgres do CI: duas requisições do mesmo par
# (inbox, contato) com nonces distintos. O lock do par precisa cobrir
# find/create + resolução (transação real), e o lock da conversa precisa
# serializar a mensagem sem deduplicar nonces diferentes.
RSpec.describe 'Connecta · admissão manual concorrente', type: :request do # rubocop:disable RSpec/DescribeClass
  self.use_transactional_tests = false

  let(:run_id) { SecureRandom.hex(4) }
  let!(:account) { create(:account) }
  let!(:channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys',
                              provider_config: { webhook_verify_token: 'valid_token' },
                              validate_provider_config: false, received_messages: false)
  end
  let!(:inbox) { channel.inbox.tap { |record| record.update!(enable_auto_assignment: false) } }
  let!(:contact) { create(:contact, account: account) }
  let!(:org) { Connecta::Scope::OrgUnit.create!(name: 'Setor A', path: "/conc-#{run_id}/a/") }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:acl_state) { Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current) }
  let(:wp_response) do
    {
      'status' => 'active', 'reused' => false, 'case_protocol' => 'BND00000002',
      'session_ref' => '888', 'case_version' => 1, 'org_unit_id' => org.id.to_s
    }
  end

  before do
    stub_const(
      'ENV',
      ENV.to_h.merge(
        'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
        'CONNECTA_RECEPTION_ORG_UNIT_ID' => org.id.to_s
      )
    )
    Connecta::Scope::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
    Connecta::UserGrant.create!(user_id: agent.id, org_unit_id: org.id, permission: 'atender')
    Connecta::Scope::UserAuthEpoch.create!(user_id: agent.id, epoch: 1)
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Redis::Alfred).to receive(:lpush)
    allow(Redis::Alfred).to receive(:lrem)
    allow(Redis::Alfred).to receive(:delete)

    client = instance_double(Connecta::Runtime::PlatformClient)
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(client).to receive(:post).and_return(wp_response)

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
    Connecta::UserGrant.where(user_id: agent.id).delete_all
    Connecta::Scope::UserAuthEpoch.where(user_id: agent.id).delete_all
    Connecta::Scope::AclSyncState.where(id: acl_state.id).delete_all
    ContactInbox.where(inbox_id: inbox.id).delete_all
    Connecta::Scope::OrgUnit.where('path LIKE ?', "/conc-#{run_id}/%").delete_all

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
      org_units_by_prefix: Connecta::Scope::OrgUnit.where('path LIKE ?', "/conc-#{run_id}/%").count,
      conversation_scopes_by_inbox: Connecta::Scope::ConversationScope.where(inbox_id: inbox.id).count,
      contact_inboxes_by_inbox: ContactInbox.where(inbox_id: inbox.id).count
    )
    expect(leftovers.reject { |_table, count| count.zero? }).to eq({}) # rubocop:disable RSpec/ExpectInHook
  end

  after(:all) do
    Connecta::Runtime::Installer.uninstall_reception_callback!
  end

  it 'duas requisições do mesmo par criam UMA conversa e dois nonces geram DUAS mensagens',
     :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    source = "55119#{SecureRandom.random_number(8).to_s.rjust(8, '0')}"
    headers = agent.create_new_auth_token
    path = "/api/v1/accounts/#{account.id}/conversations/connecta_manual_admission"
    ready = Queue.new
    go = Queue.new

    threads = %w[conc-a conc-b].map do |nonce|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.headers.merge!(headers)
          ready << true
          go.pop
          session.post(
            path,
            params: {
              inbox_id: inbox.id, contact_id: contact.id, source_id: source,
              org_unit_id: org.id.to_s, idempotency_key: nonce,
              message: { content: "texto #{nonce}" }
            },
            as: :json
          )
          [session.response.status, session.response.body]
        end
      end
    end

    2.times { ready.pop }
    2.times { go << true }
    results = threads.map(&:value)
    expect(results.map(&:first)).to all(be_in([200, 201]))
    expect(Conversation.where(inbox: inbox).count).to eq(1)

    conversation = Conversation.find_by!(inbox: inbox)
    expect(conversation.messages.where(message_type: :outgoing).order(:id).pluck(:content))
      .to contain_exactly('texto conc-a', 'texto conc-b')
    scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: conversation.id)
    expect(scope).to have_attributes(state: 'active', case_protocol: 'BND00000002', case_version: 1)
    expect(scope.org_unit_id).to eq(org.id)
  ensure
    threads&.each do |thread|
      thread.join(10) if thread.alive?
      thread.kill if thread.alive?
    end
    ActiveRecord::Base.connection_pool.release_connection
  end
end
