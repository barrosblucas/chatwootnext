require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_transfer_schema'

# Atribuição ao primeiro operador humano (substitui o round-robin da inbox
# do número humano, desligado no deploy via `enable_auto_assignment`).
# Sem assignee, a primeira mensagem pública de saída de um agente (User)
# com escrita liberada pelo Gate vira o assignee da conversa escopada.
# Bot/relay (`connecta_bot`/`relay_origin == 'bot'`), ecos sem sender,
# privada/atividade/template, automação/campanha e usuário de serviço da
# recepção nunca atribuem; assignee existente (humano ou bot) nunca é
# sobrescrito. Gate, grants e auditoria são os reais; só o conector
# WhatsApp e o push do CSAT são stubados. Arquivo não transacional (o
# exemplo de concorrência usa threads com conexões próprias) com limpeza
# espelhada em `scope_conversation_resolution_spec.rb`.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta · atribuição ao primeiro operador humano' do # rubocop:disable RSpec/DescribeClass
  include_context 'with connecta g0 scope fixture'
  self.use_transactional_tests = false

  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let(:connector) { instance_double(Whatsapp::SendOnWhatsappService, perform: nil) }

  before do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(connector)
    whatsapp_inbox.update!(enable_auto_assignment: false)
    control_inbox.update!(enable_auto_assignment: false)
  end

  after do
    example_conversation_ids = Conversation.where(account_id: account.id).pluck(:id)
    inbox_ids = Inbox.where(account_id: account.id).pluck(:id)
    user_ids = [agent_a, agent_b, manager_a, admin_nominal, member_without_grant, native_admin].map(&:id)
    Connecta::Transfer::OutboundDispatchRecord.where(conversation_id: example_conversation_ids).delete_all
    Connecta::Transfer::TransferRecord.where(
      'source_conversation_id IN (?) OR destination_conversation_id IN (?)',
      example_conversation_ids, example_conversation_ids
    ).delete_all
    Connecta::Scope::ConversationScope.where(conversation_id: example_conversation_ids).delete_all
    Connecta::Scope::ScopedInbox.where(inbox_id: inbox_ids).delete_all
    ContactInbox.where(inbox_id: inbox_ids).delete_all
    InboxMember.where(inbox_id: inbox_ids).delete_all
    Connecta::Scope::UserGrant.where(user_id: user_ids).delete_all
    Connecta::Scope::UserAuthEpoch.where(user_id: user_ids).delete_all
    Connecta::Scope::AccessAudit.where(user_id: user_ids).delete_all
    Connecta::Scope::AclSyncState.where(id: projection_heartbeat.id).delete_all
    Connecta::Scope::OrgUnit.where(id: [org_root.id, org_a.id, org_a1.id, org_b.id]).delete_all
    InternalChat::Channel.where(account_id: account.id).destroy_all
    UserSession.where(user_id: user_ids).delete_all
    Current.reset

    connection = ActiveRecord::Base.connection
    account_tables = (connection.tables - ['accounts']).select { |table| connection.column_exists?(table, :account_id) }
    account_tables.each do |table|
      connection.delete("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
    end
    Account.where(id: account.id).delete_all
    User.where(id: user_ids).delete_all
  end

  def outgoing_from(user, conversation, attrs = {})
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conversation,
                     sender: user, message_type: :outgoing, content: 'posso ajudar',
                     **attrs)
  end

  describe 'primeira resposta humana atribui (AC1)' do
    it 'primeira mensagem pública de saída do operador vira assignee' do
      expect(conv_a.reload.assignee).to be_nil

      outgoing_from(agent_a, conv_a)

      expect(conv_a.reload.assignee).to eq(agent_a)
    end

    it 'segunda mensagem de outro operador não rouba a conversa' do
      outgoing_from(agent_a, conv_a)
      outgoing_from(agent_b, conv_a)

      expect(conv_a.reload.assignee).to eq(agent_a)
    end

    it 'não sobrescreve assignee gravado depois da leitura (releitura sob lock)' do
      stub_const('ENV', ENV.to_h.except('CONNECTA_HUMAN_NUMBER_ENABLED'))
      message = outgoing_from(agent_a, conv_a)
      stub_const('ENV', ENV.to_h.merge('CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
      conv_a.update_column(:assignee_id, agent_b.id)

      expect { Connecta::Scope::FirstAgentAssignment.assign_from(message.reload) }.not_to raise_error
      expect(conv_a.reload.assignee).to eq(agent_b)
    end

    it 'no-op quando já existe assignee humano' do
      conv_a.update!(assignee: agent_b)

      expect { outgoing_from(agent_a, conv_a) }.not_to(change { conv_a.reload.assignee })
      expect(conv_a.reload.assignee).to eq(agent_b)
    end

    it 'no-op quando a conversa está com o bot (assignee_agent_bot_id)' do
      bot = create(:agent_bot)
      begin
        conv_a.update_column(:assignee_agent_bot_id, bot.id)

        expect { outgoing_from(agent_a, conv_a) }.not_to(change { conv_a.reload.assignee })
        expect(conv_a.reload.assignee).to be_nil
      ensure
        conv_a.update_column(:assignee_agent_bot_id, nil)
        bot.destroy!
      end
    end

    it 'no-op para mensagem privada' do
      expect { outgoing_from(agent_a, conv_a, private: true) }.not_to(change { conv_a.reload.assignee })
    end

    it 'no-op para mensagem entrante' do
      expect do
        create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                         sender: contact_a, message_type: :incoming, content: 'voltei')
      end.not_to(change { conv_a.reload.assignee })
    end

    it 'no-op para atividade e template' do
      expect do
        create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                         sender: agent_a, message_type: :activity, content: 'atividade')
      end.not_to(change { conv_a.reload.assignee })

      expect do
        create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                         sender: agent_a, message_type: :template, content: 'template')
      end.not_to(change { conv_a.reload.assignee })
    end

    it 'no-op para automação e campanha' do
      expect do
        outgoing_from(agent_a, conv_a, content_attributes: { 'automation_rule_id' => 7 })
      end.not_to(change { conv_a.reload.assignee })

      expect do
        outgoing_from(agent_a, conv_a, additional_attributes: { 'campaign_id' => 3 })
      end.not_to(change { conv_a.reload.assignee })
    end

    it 'no-op para bot/relay (connecta_bot e relay_origin bot)' do
      expect do
        outgoing_from(agent_a, conv_a, content_attributes: { 'connecta_bot' => true })
      end.not_to(change { conv_a.reload.assignee })

      expect do
        outgoing_from(agent_a, conv_a, content_attributes: { 'relay_origin' => 'bot' })
      end.not_to(change { conv_a.reload.assignee })
    end

    it 'no-op para usuário de serviço da recepção' do
      stub_const('ENV', ENV.to_h.merge('CONNECTA_RECEPTION_SENDER_USER_IDS' => agent_a.id.to_s))

      expect { outgoing_from(agent_a, conv_a) }.not_to(change { conv_a.reload.assignee })
    end

    it 'no-op em inbox não marcada' do
      expect do
        create(:message, account: account, inbox: control_inbox, conversation: conv_control,
                         sender: agent_a, message_type: :outgoing, content: 'fora do escopo')
      end.not_to(change { conv_control.reload.assignee })
    end

    it 'no-op com o recurso desligado' do
      stub_const('ENV', ENV.to_h.except('CONNECTA_HUMAN_NUMBER_ENABLED'))

      expect { outgoing_from(agent_a, conv_a) }.not_to(change { conv_a.reload.assignee })
    end

    it 'nega remetente sem grant (Gate) sem atribuir' do
      expect { outgoing_from(member_without_grant, conv_a) }.not_to(change { conv_a.reload.assignee })
    end

    it 'admin nativo tem escrita e atribui' do
      outgoing_from(native_admin, conv_a)

      expect(conv_a.reload.assignee).to eq(native_admin)
    end
  end

  describe 'concorrência' do
    it 'primeiras mensagens concorrentes elegem exatamente um assignee sem erro' do
      grant_b = Connecta::Scope::UserGrant.create!(user_id: agent_b.id, org_unit: org_a, permission: 'atender')
      begin
        stub_const('ENV', ENV.to_h.except('CONNECTA_HUMAN_NUMBER_ENABLED'))
        first_id = outgoing_from(agent_a, conv_a).id
        second_id = outgoing_from(agent_b, conv_a).id
        stub_const('ENV', ENV.to_h.merge('CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))

        errors = []
        threads = [first_id, first_id, second_id, second_id].map do |message_id|
          Thread.new do
            Connecta::Scope::FirstAgentAssignment.assign_from(Message.find(message_id))
          rescue StandardError => e
            errors << e
          end
        end
        threads.each(&:join)

        expect(errors).to be_empty
        expect([agent_a.id, agent_b.id]).to include(conv_a.reload.assignee_id)
      ensure
        grant_b.destroy!
      end
    end
  end

  describe 'destino de transferência (AC2)' do
    let(:origin_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }
    let(:transfer) { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b) }

    it 'aviso do bot não atribui; primeira mensagem humana do destino atribui' do
      expect(transfer.begin!).to eq(:proceed)
      destination = transfer.commit_local!(target_case_version: 2,
                                           summary: 'Assunto: a. Feito: b. Pendencia: c.')

      expect(destination.reload.assignee).to be_nil

      transfer.activate!(case_version: 2)
      create(:message, account: account, inbox: whatsapp_inbox, conversation: destination,
                       sender: agent_b, message_type: :outgoing, content: 'assumo por aqui')

      expect(destination.reload.assignee).to eq(agent_b)
    end
  end

  describe 'CSAT de ponta a ponta carrega o atendente (AC3)' do
    it 'primeira mensagem atribui, resolve mantém, resposta e push levam id e nome' do
      outgoing_from(agent_a, conv_a)
      expect(conv_a.reload.assignee).to eq(agent_a)

      conv_a.update!(status: :resolved)
      expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).state).to eq('closed')

      reply = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                               sender: contact_a, message_type: :incoming, content_type: :input_csat,
                               content_attributes: { 'submitted_values' =>
                                 { 'csat_survey_response' => { 'rating' => 5 } } })
      response = CsatSurveys::ResponseBuilder.new(message: reply).perform

      expect(response.assigned_agent).to eq(agent_a)

      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s,
                                       'CONNECTA_PLATFORM_URL' => 'https://wp.example',
                                       'CONNECTA_FORK_TO_PLATFORM_SECRET' => 's3cret'))
      client = instance_double(Connecta::Runtime::PlatformClient)
      allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
      posted = nil
      allow(client).to receive(:post) { |path, payload| posted = [path, payload] }

      Connecta::Runtime::CsatPushJob.new.perform(response.id)

      expect(posted[0]).to eq('/attendance/v1/csat')
      expect(posted[1]).to include(assigned_agent_id: agent_a.id,
                                   assigned_agent_name: agent_a.available_name)
    end
  end
end
