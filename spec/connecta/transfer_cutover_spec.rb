require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_transfer_schema'

# T0.3 (spike G0): corte temporal da transferência entre setores na MESMA inbox Baileys. Mensagens entram pelo serviço real
# (Whatsapp::IncomingMessageBaileysService) em threads; a transferência é a transação real (Connecta::Transfer::LocalTransaction).
# Sem transação externa (use_transactional_tests = false): cada thread usa a própria conexão. A limpeza remove só as linhas
# criadas neste exemplo: por conta (tabelas com account_id) e, para transfers/dispatches (sem account_id), por conversas
# da inbox do exemplo, ANTES de apagar as conversas. Linhas antigas de outros exemplos são preservadas.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta G0 · corte temporal da transferência (T0.3)' do # rubocop:disable RSpec/DescribeClass
  self.use_transactional_tests = false

  # Antes dos let!: a primeira mensagem (semente) já passa pelos stubs.
  before do
    stub_request(:get, /profile-picture-url/).to_return(status: 200, body: { data: { profilePictureUrl: nil } }.to_json)
    # Lock de contato em Redis (MockRedis, com espera por polling) sofre inanição entre threads e estoura em 5 s. Fica fora da prova:
    # a serialização entre mensagens e transferência é a do Postgres (IncomingHook e LocalTransaction).
    allow_any_instance_of(Whatsapp::IncomingMessageBaileysService).to receive(:with_contact_lock) { |_phone, &block| block.call } # rubocop:disable RSpec/AnyInstance
  end

  let(:token) { 'valid_token' }
  let(:clock) { -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
  # Dados únicos por execução: nada com valor fixo, para não colidir com outros specs no mesmo banco.
  let(:run_id) { SecureRandom.hex(4) }
  let(:run_digits) { format('%08d', SecureRandom.random_number(10**8)) }
  let(:lid_jid) { "9#{run_digits}@lid" }
  let(:phone_jid) { "5511#{run_digits}@s.whatsapp.net" }

  # Mensagem de contato individual (LID com JID de telefone), no formato do messages.upsert do baileys-api.
  let(:deliver) do
    lambda do |source_id|
      params = {
        webhookVerifyToken: token,
        event: 'messages.upsert',
        data: {
          type: 'notify',
          messages: [{
            key: { id: source_id, remoteJid: lid_jid, remoteJidAlt: phone_jid, fromMe: false, addressingMode: 'lid' },
            pushName: 'Cidadao T03',
            messageTimestamp: Time.current.to_i,
            message: { conversation: "texto #{source_id}" }
          }]
        }
      }
      Whatsapp::IncomingMessageBaileysService.new(inbox: whatsapp_inbox, params: params).perform
    end
  end

  # Provedor Baileys sem rede (mesmas flags do spec de Baileys): sem validar credenciais e com aviso de recebimento stubado pela fábrica.
  # A inbox é criada pela fábrica do canal; sem auto-atribuição, como a inbox física (sem round-robin no MockRedis).
  let!(:account) { create(:account) }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: { webhook_verify_token: token },
                              validate_provider_config: false, received_messages: false)
  end
  let!(:whatsapp_inbox) { whatsapp_channel.inbox.tap { |inbox| inbox.update!(name: "Caixa T03 #{run_id}", enable_auto_assignment: false) } }
  let!(:other_inbox) { create(:inbox, account: account, name: "Caixa vizinha T03 #{run_id}") }
  let!(:org_a) { Connecta::Scope::OrgUnit.create!(name: 'Setor A', path: "/t03-#{run_id}/a/") }
  let!(:org_b) { Connecta::Scope::OrgUnit.create!(name: 'Setor B', path: "/t03-#{run_id}/b/") }

  # Primeira mensagem sem escopo: caminho nativo cria a conversa de origem; depois o escopo ativo é gravado para ela.
  let!(:origin_conversation) do
    deliver.call('msg-0')
    Conversation.find_by!(inbox: whatsapp_inbox)
  end
  let!(:origin_scope) do
    Connecta::Scope::ConversationScope.create!(conversation_id: origin_conversation.id, inbox_id: whatsapp_inbox.id,
                                               contact_id: origin_conversation.contact_id, org_unit: org_a, state: 'active',
                                               case_protocol: 'CASO-T03', case_version: 1)
  end

  it 'destino permanece na inbox de origem e a nota não expõe o setor anterior' do
    destination = Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b).call

    expect(destination).to be_a(Conversation)
    expect(destination.inbox_id).to eq(origin_conversation.inbox_id)
    expect(destination.inbox_id).not_to eq(other_inbox.id)
    expect(destination.messages.last.content).to include('protocolo CASO-T03')
    expect(destination.messages.last.content).not_to include('Setor A')
  end

  after do
    # Nesta execução, fonte e destino são as únicas conversas da inbox do exemplo: transfers e dispatches pertencem a
    # elas (tabelas sem account_id, localizadas por conversation_id ANTES de apagar as conversas). A limpeza abaixo
    # remove só essas linhas e as conversas da inbox; resíduos de outras execuções ficam intactos.
    example_conversation_ids = Conversation.where(inbox: whatsapp_inbox).pluck(:id)
    Connecta::Transfer::OutboundDispatchRecord.where(conversation_id: example_conversation_ids).delete_all
    Connecta::Transfer::TransferRecord.where(
      'source_conversation_id IN (?) OR destination_conversation_id IN (?)',
      example_conversation_ids, example_conversation_ids
    ).delete_all
    Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id).delete_all
    ContactInbox.where(inbox_id: whatsapp_inbox.id).delete_all
    Connecta::Scope::OrgUnit.where('path LIKE ?', "/t03-#{run_id}/%").delete_all
    connection = ActiveRecord::Base.connection
    account_tables = (connection.tables - ['accounts']).select { |table| connection.column_exists?(table, :account_id) }
    account_tables.each do |table|
      connection.delete("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
    end
    Account.where(id: account.id).delete_all

    # Sobras desta execução: por conta (todas as tabelas com account_id), por prefixo e por inbox. Tudo tem de dar zero.
    leftovers = account_tables.to_h do |table|
      rows = connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
      [table, rows.to_i]
    end
    leftovers.merge!(
      accounts: Account.where(id: account.id).count,
      org_units_by_prefix: Connecta::Scope::OrgUnit.where('path LIKE ?', "/t03-#{run_id}/%").count,
      conversation_scopes_by_inbox: Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id).count,
      contact_inboxes_by_inbox: ContactInbox.where(inbox_id: whatsapp_inbox.id).count,
      transfers_by_conversation: Connecta::Transfer::TransferRecord.where(
        'source_conversation_id IN (?) OR destination_conversation_id IN (?)',
        example_conversation_ids, example_conversation_ids
      ).count,
      dispatches_by_conversation: Connecta::Transfer::OutboundDispatchRecord.where(conversation_id: example_conversation_ids).count
    )
    expect(leftovers.reject { |_table, count| count.zero? }).to eq({}) # rubocop:disable RSpec/ExpectInHook
  end

  context 'with incoming messages racing one transfer' do
    # Cada repetição é um exemplo com dados próprios (a limpeza roda entre elas).
    [1, 2, 3, 4, 5].each do |repetition|
      # rubocop:disable RSpec/ExampleLength
      it "repetição #{repetition}: 20 mensagens concorrentes com uma transferência, cada uma em exatamente uma conversa",
         :aggregate_failures do
        ActiveRecord::Base.connection_pool.release_connection
        started = {}
        finished = {}
        window = {}
        done = Queue.new

        workers = []
        transfer = nil
        begin
          workers = (1..20).each_slice(7).map do |ids|
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                ids.each do |id|
                  started[id] = clock.call
                  deliver.call("msg-#{id}")
                  finished[id] = clock.call
                  done << id
                end
              end
            end
          end
          transfer = Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              # A transferência entra no meio da rajada: 5 mensagens já commitadas, as demais em voo ou ainda não iniciadas.
              Timeout.timeout(60) { 5.times { done.pop } }
              window[:started] = clock.call
              Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b).call
              window[:returned] = clock.call
            end
          end
          (workers + [transfer]).each(&:join)
          # Falha em thread não pode ficar silenciosa: o join acima não relança; value sim, sem mudar o caminho feliz.
          (workers + [transfer]).each(&:value)
        ensure
          # Garante que a limpeza do after não concorra com threads ainda vivas nem vaze conexão em caso de falha/timeout.
          ([transfer].compact + workers).each do |thread|
            thread.join(10) if thread.alive?
            thread.kill if thread.alive?
          end
          ActiveRecord::Base.connection_pool.release_connection
        end

        # Só mensagens do cidadão: a nota privada do destino não tem source_id.
        rows = whatsapp_inbox.messages.where.not(source_id: nil).order(:id).pluck(:id, :source_id, :conversation_id)
        destination_scope = Connecta::Scope::ConversationScope.find_by!(inbox_id: whatsapp_inbox.id, state: 'pending_activation')
        destination_conversation_id = destination_scope.conversation_id
        conversation_of = rows.to_h { |_id, source_id, conversation_id| [source_id, conversation_id] }

        # Exatamente uma linha por mensagem: nem perdida nem duplicada.
        expect(rows.size).to eq(21)
        expect(conversation_of.keys.uniq.size).to eq(21)
        expect(conversation_of.values).to all(be_in([origin_conversation.id, destination_conversation_id]))

        # Antes do commit da transferência (já terminaram antes de ela começar) ⇒ origem; depois (começaram após ela voltar) ⇒ destino.
        # A semente (id 0) é sempre anterior.
        committed_before = (0..20).select { |id| id.zero? || finished[id] < window[:started] }
        started_after = (1..20).select { |id| started[id] > window[:returned] }
        expect(started_after).not_to be_empty
        expect(conversation_of.values_at(*committed_before.map { |id| "msg-#{id}" })).to all(eq(origin_conversation.id))
        expect(conversation_of.values_at(*started_after.map { |id| "msg-#{id}" })).to all(eq(destination_conversation_id))

        # Ordem de inserção = ordem do lock: toda mensagem da origem é mais antiga que toda mensagem do destino.
        origin_rows = rows.select { |_id, _source_id, conversation_id| conversation_id == origin_conversation.id }
        destination_rows = rows.select { |_id, _source_id, conversation_id| conversation_id == destination_conversation_id }
        expect(origin_rows.map(&:first).max).to be < destination_rows.map(&:first).min

        expect(origin_scope.reload.state).to eq('transferred_out')
        expect(Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id, state: %w[active transferring]).count).to eq(0)
        expect(Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id, contact_id: origin_scope.contact_id,
                                                        state: Connecta::Scope::ConversationScope::NON_TERMINAL_STATES).count).to eq(1)
      end
      # rubocop:enable RSpec/ExampleLength
    end
  end

  it 'sem concorrência: mensagem antes da transferência fica na origem e a seguinte vai ao destino' do
    deliver.call('msg-1')
    Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b).call
    deliver.call('msg-2')

    destination_conversation = Conversation.where(inbox: whatsapp_inbox).where.not(id: origin_conversation.id).sole
    destination_scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: destination_conversation.id)

    expect(origin_conversation.messages.pluck(:content)).to contain_exactly('texto msg-0', 'texto msg-1')
    expect(destination_conversation.messages.pluck(:content)).to contain_exactly(a_string_including('protocolo CASO-T03'), 'texto msg-2')
    expect(origin_scope.reload.state).to eq('transferred_out')
    expect(destination_scope.state).to eq('pending_activation')
    expect(destination_scope.org_unit).to eq(org_b)
  end

  # Determinístico: a corrida acima raramente cai na janela entre resolver a origem e gravar a mensagem. Aqui a mensagem
  # para exatamente nessa janela; a transferência só pode commitar depois dela (o lock vale até o commit da mensagem).
  it 'mensagem já resolvida na origem e ainda em voo: a transferência espera o commit dela' do
    resolved = Queue.new
    transfer_done = Queue.new
    committed_while_in_flight = nil
    allow_any_instance_of(Whatsapp::IncomingMessageBaileysService).to receive(:handle_create_message).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      resolved << true
      committed_while_in_flight = transfer_done.pop(timeout: 0.5)
      original.call(*args)
    end

    message_thread = nil
    begin
      message_thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection { deliver.call('msg-paused') } }
      Timeout.timeout(60) { resolved.pop }
      Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b).call
      transfer_done << true
      message_thread.join(60)
      message_thread.value
    ensure
      # Desbloqueia a mensagem pausada e garante join limitado: sem isso, uma falha na transferência deixaria a thread
      # viva concorrendo com a limpeza do after (que apaga só as conversas deste exemplo).
      begin
        transfer_done << true
      rescue ClosedQueueError
        nil
      end
      if message_thread&.alive?
        message_thread.join(10)
        message_thread.kill if message_thread.alive?
      end
      ActiveRecord::Base.connection_pool.release_connection
    end

    expect(committed_while_in_flight).to be_nil
    expect(Message.find_by!(source_id: 'msg-paused').conversation_id).to eq(origin_conversation.id)
  end

  it 'segunda transferência da mesma origem falha e não cria outro destino' do
    Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b).call

    expect { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b).call }
      .to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotFound') })
    expect(Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id).count).to eq(2)
    expect(Conversation.where(inbox: whatsapp_inbox).count).to eq(2)
  end

  it 'falha ao criar o destino desfaz a origem e a conversa criada na mesma transação' do
    expect { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: nil).call }
      .to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::NotNullViolation') })

    expect(origin_scope.reload.state).to eq('active')
    expect(Conversation.where(inbox: whatsapp_inbox).count).to eq(1)
    expect(Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id).count).to eq(1)
  end
end
