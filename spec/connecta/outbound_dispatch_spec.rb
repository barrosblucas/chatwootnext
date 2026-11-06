require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_transfer_schema'

# T0.7b (spike G0): despacho de saída de inbox marcada com barreira de transferência. A mensagem entra por create(:message), o enqueue
# acontece na criação e o SendReplyJob real roda com o hook; só o conector (Whatsapp::SendOnWhatsappService) é stubado, sem rede.
# Quem prova "um envio, nenhum depois da transferência" é o UPDATE condicional do Postgres, não o lock de canal em Redis.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta G0 · despacho de saída e barreira de transferência (T0.7b)' do # rubocop:disable RSpec/DescribeClass, RSpec/MultipleDescribes
  include_context 'with connecta g0 scope fixture'

  let(:connector) { instance_double(Whatsapp::SendOnWhatsappService, perform: nil) }
  let(:dispatches) { Connecta::Transfer::OutboundDispatchRecord }
  let(:origin_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }
  let(:outgoing) { create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'resposta') }

  before do
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(connector)
  end

  it 'scope active: a mensagem entra em queued, o job chama o conector uma vez e a linha vira accepted' do
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('queued')

    2.times { SendReplyJob.perform_now(outgoing.id) }

    expect(connector).to have_received(:perform).once
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('accepted')
  end

  it 'late worker: mensagem enfileirada com escopo active e depois transferring nunca chega ao conector e vira parked' do
    outgoing
    origin_scope.update!(state: 'transferring')

    SendReplyJob.perform_now(outgoing.id)

    expect(connector).not_to have_received(:perform)
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('parked')
  end

  it 'prepare_transfer! parka o queued e não espera' do
    outgoing
    origin_scope.update!(state: 'transferring')

    result = Connecta::Transfer::OutboundDispatch.prepare_transfer!(conv_a)

    expect(result).to have_attributes(parked: 1, wait: false)
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('parked')
  end

  it 'prepare_transfer! espera o envio em voo (dispatching) e deixa a linha como está' do
    outgoing
    dispatches.find_by!(message_id: outgoing.id).update!(state: 'dispatching')

    result = Connecta::Transfer::OutboundDispatch.prepare_transfer!(conv_a)

    expect(result).to have_attributes(parked: 0, wait: true)
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('dispatching')
  end

  it 'prepare_transfer! com uncertain levanta conflito, mantém a transferência e não para nenhum queued' do
    ambiguous = outgoing
    dispatches.find_by!(message_id: ambiguous.id).update!(state: 'uncertain')
    queued = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'outra')

    expect { Connecta::Transfer::OutboundDispatch.prepare_transfer!(conv_a) }
      .to(raise_error { |error| expect(error.class.name).to eq('Connecta::Transfer::OutboundDispatch::ConflictError') })
    expect(dispatches.find_by!(message_id: queued.id).state).to eq('queued')
    expect(dispatches.find_by!(message_id: ambiguous.id).state).to eq('uncertain')
  end

  it 'timeout do conector vira uncertain e o job seguinte não reenvia' do
    allow(connector).to receive(:perform).and_raise(Net::ReadTimeout)
    outgoing

    expect { SendReplyJob.perform_now(outgoing.id) }.to raise_error(Net::ReadTimeout)
    expect { SendReplyJob.perform_now(outgoing.id) }.not_to raise_error

    expect(connector).to have_received(:perform).once
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('uncertain')
  end

  it '409 do provedor (envio já em processamento) volta a queued e o retry reenvia sob o mesmo id' do
    allow(connector).to receive(:perform).and_raise(Whatsapp::Providers::WhatsappBaileysService::MessageAlreadyProcessingError)
    outgoing

    # O retry nativo do SendReplyJob (60s) intercepta o 409: o hook devolve a linha
    # ao estado claimável em vez de marcá-la uncertain (outro worker detém o lock).
    expect { SendReplyJob.perform_now(outgoing.id) }.not_to raise_error
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('queued')

    allow(connector).to receive(:perform).and_return(nil)
    SendReplyJob.perform_now(outgoing.id)

    expect(connector).to have_received(:perform).twice
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('accepted')
  end

  it 'retry de job para mensagem já enviada reconcilia e não chama o conector de novo' do
    outgoing.update!(source_id: 'provider-abc')

    SendReplyJob.perform_now(outgoing.id)

    expect(connector).not_to have_received(:perform)
    expect(dispatches.find_by!(message_id: outgoing.id)).to have_attributes(
      state: 'accepted', connector_message_id: 'provider-abc'
    )
  end

  it 'erro comum do conector vira failed e não é reenviado' do
    allow(connector).to receive(:perform).and_raise(StandardError, 'provedor recusou')
    outgoing

    expect { SendReplyJob.perform_now(outgoing.id) }.to raise_error(StandardError, 'provedor recusou')
    SendReplyJob.perform_now(outgoing.id)

    expect(connector).to have_received(:perform).once
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('failed')
  end

  it 'inbox não marcada: o envio segue o caminho nativo e não cria linha de despacho' do
    native = instance_double(Messages::SendEmailNotificationService, perform: nil)
    allow(Messages::SendEmailNotificationService).to receive(:new).and_return(native)
    control_message = create(:message, account: account, conversation: conv_control, message_type: :outgoing, content: 'controle')

    SendReplyJob.perform_now(control_message.id)

    expect(native).to have_received(:perform).once
    expect(connector).not_to have_received(:perform)
    expect(dispatches.where(message_id: control_message.id)).to be_empty
  end
end

RSpec.describe 'Connecta G0 · envio em recepção só pelo usuário de serviço (CONNECTA_RECEPTION_SENDER_USER_IDS)' do
  include_context 'with connecta g0 scope fixture'

  let(:connector) { instance_double(Whatsapp::SendOnWhatsappService, perform: nil) }
  let(:dispatches) { Connecta::Transfer::OutboundDispatchRecord }
  let(:origin_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }
  let(:bot_user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :administrator, account: account) }
  let(:parked_error) { Connecta::Transfer::OutboundDispatch::PARKED_VISIBLE_ERROR }

  before do
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(connector)
    origin_scope.update!(state: 'reception')
  end

  it 'reception + usuário configurado: o job chama o conector uma vez e a linha vira accepted' do
    with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => bot_user.id.to_s) do
      message = create(:message, account: account, conversation: conv_a, message_type: :outgoing, sender: bot_user, content: 'menu')

      SendReplyJob.perform_now(message.id)

      expect(connector).to have_received(:perform).once
      expect(dispatches.find_by!(message_id: message.id).state).to eq('accepted')
      expect(message.reload.failed?).to be(false)
    end
  end

  it 'reception + outro usuário (inclusive admin): não envia, vira parked e a mensagem aparece como falha' do
    with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => bot_user.id.to_s) do
      message = create(:message, account: account, conversation: conv_a, message_type: :outgoing, sender: admin_user, content: 'resposta')

      SendReplyJob.perform_now(message.id)

      expect(connector).not_to have_received(:perform)
      expect(dispatches.find_by!(message_id: message.id).state).to eq('parked')
      expect(message.reload.failed?).to be(true)
      expect(message.external_error).to eq(parked_error)
    end
  end

  it 'reception + config vazia: nada liberado, parked com falha visível' do
    with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => '') do
      message = create(:message, account: account, conversation: conv_a, message_type: :outgoing, sender: bot_user, content: 'menu')

      SendReplyJob.perform_now(message.id)

      expect(connector).not_to have_received(:perform)
      expect(dispatches.find_by!(message_id: message.id).state).to eq('parked')
      expect(message.reload.failed?).to be(true)
      expect(message.external_error).to eq(parked_error)
    end
  end

  it 'transferring: continua parked, agora com falha visível para o agente' do
    with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => bot_user.id.to_s) do
      origin_scope.update!(state: 'transferring')
      message = create(:message, account: account, conversation: conv_a, message_type: :outgoing, sender: bot_user, content: 'menu')

      SendReplyJob.perform_now(message.id)

      expect(connector).not_to have_received(:perform)
      expect(dispatches.find_by!(message_id: message.id).state).to eq('parked')
      expect(message.reload.failed?).to be(true)
      expect(message.external_error).to eq(parked_error)
    end
  end

  it 'manutenção: parked sem marcar falha (fluxo de manutenção preservado)' do
    with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => bot_user.id.to_s) do
      origin_scope.update!(state: 'active')
      marked_inbox.update!(maintenance: true)
      message = create(:message, account: account, conversation: conv_a, message_type: :outgoing, sender: bot_user, content: 'menu')

      SendReplyJob.perform_now(message.id)

      expect(connector).not_to have_received(:perform)
      expect(dispatches.find_by!(message_id: message.id).state).to eq('parked')
      expect(message.reload.failed?).to be(false)
    end
  end
end

RSpec.describe Connecta::Runtime::Feature do
  describe '.reception_sender_user_ids' do
    it 'lê a lista de ids separados por vírgula' do
      with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => '5, 7') do
        expect(described_class.reception_sender_user_ids).to eq([5, 7])
      end
    end

    it 'vazia ou ausente = nada liberado' do
      with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => '') do
        expect(described_class.reception_sender_user_ids).to eq([])
      end
      with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => nil) do
        expect(described_class.reception_sender_user_ids).to eq([])
      end
    end

    it 'ignora valores inválidos e não positivos' do
      with_modified_env('CONNECTA_RECEPTION_SENDER_USER_IDS' => '5, abc, -3, 0, 5') do
        expect(described_class.reception_sender_user_ids).to eq([5])
      end
    end
  end
end

# Sem transação externa (use_transactional_tests = false): cada thread usa a própria conexão. A limpeza remove só as linhas
# criadas por este exemplo; os dados são únicos por execução.
RSpec.describe 'Connecta G0 · claim concorrente do mesmo envio (T0.7b)' do # rubocop:disable RSpec/DescribeClass
  self.use_transactional_tests = false

  let(:run_id) { SecureRandom.hex(4) }
  let(:dispatches) { Connecta::Transfer::OutboundDispatchRecord }

  let!(:account) { create(:account) }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys', provider_config: { webhook_verify_token: 'valid_token' },
                              validate_provider_config: false, received_messages: false)
  end
  let!(:inbox) { whatsapp_channel.inbox.tap { |record| record.update!(name: "Caixa T07b #{run_id}", enable_auto_assignment: false) } }
  let!(:org_unit) { Connecta::Scope::OrgUnit.create!(name: 'Setor T07b', path: "/t07b-#{run_id}/a/") }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    Connecta::Scope::ConversationScope.create!(conversation_id: conversation.id, inbox_id: inbox.id, contact_id: contact.id,
                                               org_unit: org_unit, state: 'active', case_protocol: "CASO-T07B-#{run_id}", case_version: 1)
    Connecta::Scope::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
  end

  after do
    dispatches.where(conversation_id: conversation.id).delete_all
    Connecta::Scope::ConversationScope.where(inbox_id: inbox.id).delete_all
    Connecta::Scope::ScopedInbox.where(inbox_id: inbox.id).delete_all
    ContactInbox.where(inbox_id: inbox.id).delete_all
    Connecta::Scope::OrgUnit.where('path LIKE ?', "/t07b-#{run_id}/%").delete_all
    connection = ActiveRecord::Base.connection
    account_tables = (connection.tables - ['accounts']).select { |table| connection.column_exists?(table, :account_id) }
    # A conta nasce com chat interno (after_create_commit) que aponta para os próprios canais: sem gatilhos de FK, a ordem das tabelas não importa.
    connection.execute('SET session_replication_role = replica')
    begin
      account_tables.each do |table|
        connection.delete("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
      end
      Account.where(id: account.id).delete_all
    ensure
      connection.execute('SET session_replication_role = DEFAULT')
    end

    # Sobras desta execução: por conta (todas as tabelas com account_id), por prefixo e por inbox. Tudo tem de dar zero.
    leftovers = account_tables.to_h do |table|
      rows = connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
      [table, rows.to_i]
    end
    leftovers.merge!(
      accounts: Account.where(id: account.id).count,
      org_units_by_prefix: Connecta::Scope::OrgUnit.where('path LIKE ?', "/t07b-#{run_id}/%").count,
      conversation_scopes_by_inbox: Connecta::Scope::ConversationScope.where(inbox_id: inbox.id).count,
      contact_inboxes_by_inbox: ContactInbox.where(inbox_id: inbox.id).count,
      dispatches_by_conversation: dispatches.where(conversation_id: conversation.id).count
    )
    expect(leftovers.reject { |_table, count| count.zero? }).to eq({}) # rubocop:disable RSpec/ExpectInHook
  end

  it 'duas threads disparam o mesmo envio: o conector roda uma vez e a linha vira accepted' do
    # Remetente é o contato: a fábrica criaria um usuário, e a tabela users não tem account_id, então a limpeza não o alcançaria.
    message = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: contact, content: 'concorrente')
    calls = Queue.new
    allow(Whatsapp::SendOnWhatsappService).to receive(:new) do
      calls << true
      sleep 0.2
      instance_double(Whatsapp::SendOnWhatsappService, perform: nil)
    end

    threads = Array.new(2) do
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { SendReplyJob.perform_now(message.id) } }
    end
    threads.each(&:join)

    expect(calls.size).to eq(1)
    expect(dispatches.find_by!(message_id: message.id).state).to eq('accepted')
  end
end
