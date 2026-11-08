require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_transfer_schema'

# Decisão 005 (ciclo de vida do escopo na resolução/reabertura): resolver move o
# escopo a `closed` (terminal, legível, sem reuso); mensagem do cidadão depois de
# resolvido não reabre (conversa nova em `reception` pelo fluxo nativo);
# reabrir (resolved→open) restaura o mesmo atendimento a `active`; escrita em
# resolvida nega 403 inclusive para admin nativo. Gate, hooks e reuso são os
# reais; nenhuma decisão de autorização é mockada.
# Specs escritas para a validação consolidada; esta frente não executa rspec.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · ciclo de vida do escopo na resolução/reabertura (decisão 005)', type: :request do
  include_context 'with connecta g0 scope fixture'
  self.use_transactional_tests = false

  let(:messages_path) { "#{conversations_path}/#{conv_a.display_id}/messages" }
  let(:toggle_path) { "#{conversations_path}/#{conv_a.display_id}/toggle_status" }
  let(:scope_of_conv_a) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }

  before do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_HUMAN_NUMBER_ENABLED' => 'true'))
    create(:inbox_member, inbox: whatsapp_inbox, user: native_admin)
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
    Connecta::Scope::ConversationScope.where(inbox_id: whatsapp_inbox.id).delete_all
    Connecta::Scope::ScopedInbox.where(inbox_id: whatsapp_inbox.id).delete_all
    ContactInbox.where(inbox_id: inbox_ids).delete_all
    InboxMember.where(inbox_id: inbox_ids).delete_all
    Connecta::Scope::UserGrant.where(user_id: user_ids).delete_all
    Connecta::Scope::UserAuthEpoch.where(user_id: user_ids).delete_all
    Connecta::Scope::AccessAudit.where(user_id: user_ids).delete_all
    Connecta::Scope::AclSyncState.where(id: projection_heartbeat.id).delete_all
    Connecta::Scope::OrgUnit.where(id: [org_root.id, org_a.id, org_a1.id, org_b.id]).delete_all
    InternalChat::Channel.where(account_id: account.id).destroy_all
    UserSession.where(user_id: user_ids).delete_all

    connection = ActiveRecord::Base.connection
    account_tables = (connection.tables - ['accounts']).select { |table| connection.column_exists?(table, :account_id) }
    account_tables.each do |table|
      connection.delete("DELETE FROM #{connection.quote_table_name(table)} WHERE account_id = #{account.id.to_i}")
    end
    Account.where(id: account.id).delete_all
    User.where(id: user_ids).delete_all
  end

  describe 'resolver move o escopo a terminal (AC1)' do
    it 'active vira closed mantendo setor, protocolo, versão e carimbando closed_at' do
      expect { conv_a.update!(status: :resolved) }
        .to change { scope_of_conv_a.reload.state }.from('active').to('closed')

      expect(scope_of_conv_a).to have_attributes(org_unit_id: org_a.id, case_protocol: 'CASO-A', case_version: 1)
      expect(scope_of_conv_a.closed_at).not_to be_nil
      expect(conv_a.reload.status).to eq('resolved')
    end

    it 'é idempotente: resolver de novo não muda nem erra' do
      conv_a.update!(status: :resolved)

      expect { Connecta::Scope::ConversationResolution.resolve_scope!(conv_a.reload) }.not_to raise_error
      expect(scope_of_conv_a.reload.state).to eq('closed')
    end

    it 'inbox não marcada segue nativa (sem escopo, sem erro)' do
      expect { conv_control.update!(status: :resolved) }.not_to raise_error

      expect(conv_control.reload.status).to eq('resolved')
      expect(Connecta::Scope::ConversationScope.find_by(conversation_id: conv_control.id)).to be_nil
    end

    it 'flag desligada mantém o comportamento atual (active continua active)' do
      stub_const('ENV', ENV.to_h.except('CONNECTA_HUMAN_NUMBER_ENABLED'))

      expect { conv_b.update!(status: :resolved) }.not_to raise_error

      expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_b.id).state).to eq('active')
    end

    it 'activation_stuck vira closed (terminal)' do
      scope_of_conv_a.update!(state: 'activation_stuck')

      expect { conv_a.update!(status: :resolved) }
        .to change { scope_of_conv_a.reload.state }.from('activation_stuck').to('closed')
    end

    it 'pending_activation fecha e marca o transfer como activation_stuck' do
      scope_of_conv_a.update!(state: 'pending_activation', case_version: 0)
      record = Connecta::Transfer::TransferRecord.create!(
        source_conversation_id: conv_a1.id, destination_conversation_id: conv_a.id,
        destination_org_unit_id: org_b.id, state: 'committed_local', target_case_version: 1
      )

      conv_a.update!(status: :resolved)

      expect(scope_of_conv_a.reload.state).to eq('closed')
      expect(record.reload.state).to eq('activation_stuck')
    end

    it 'transferring aborta o preparo pré-commit e fecha a origem' do
      scope_of_conv_a.update!(state: 'transferring')
      record = Connecta::Transfer::TransferRecord.create!(
        source_conversation_id: conv_a.id, destination_org_unit_id: org_b.id,
        state: 'requested', target_case_version: 1
      )

      conv_a.update!(status: :resolved)

      expect(scope_of_conv_a.reload.state).to eq('closed')
      expect(record.reload.state).to eq('aborted')
    end

    it 'prepared com platform_session_ref enfileira abort remoto uma vez, após o fechamento' do
      scope_of_conv_a.update!(state: 'transferring')
      record = Connecta::Transfer::TransferRecord.create!(
        source_conversation_id: conv_a.id, destination_org_unit_id: org_b.id,
        state: 'prepared', platform_session_ref: 'sess-prepared', target_case_version: 1
      )

      expect { conv_a.update!(status: :resolved) }
        .to have_enqueued_job(Connecta::Runtime::TransferAbortJob)
        .with(record.id, 'conversation_resolved')
      expect(scope_of_conv_a.reload.state).to eq('closed')
      expect(record.reload.state).to eq('aborted')

      expect { Connecta::Scope::ConversationResolution.resolve_scope!(conv_a.reload) }
        .not_to have_enqueued_job(Connecta::Runtime::TransferAbortJob)
    end

    it 'transferred_out continua terminal e não é reaberto pela resolução' do
      scope_of_conv_a.update!(state: 'transferred_out')

      expect { conv_a.update!(status: :resolved) }
        .not_to(change { scope_of_conv_a.reload.state })
    end
  end

  describe 'mensagem do cidadão após resolver não reabre (AC2)' do
    before { conv_a.update!(status: :resolved) }

    it 'mensagem entrante na conversa resolvida não muda o status nem o escopo' do
      expect do
        create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                         sender: contact_a, message_type: :incoming, content: 'voltei')
      end.to change(Message, :count).by(1)

      expect(conv_a.reload.status).to eq('resolved')
      expect(scope_of_conv_a.reload.state).to eq('closed')
    end

    it 'o reuso não reaproveita escopo closed: resolve devolve nil (cria conversa nova)' do
      expect(Connecta::Scope::ConversationReuse.resolve(user: agent_a, inbox: whatsapp_inbox, contact: contact_a)).to be_nil
    end

    it 'conversa nova do mesmo par ganha escopo reception (menu de triagem)' do
      stub_const('ENV', ENV.to_h.merge('CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                                       'CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))
      fresh = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_a)

      scope = Connecta::Runtime::ReceptionScopeCreator.call(fresh)

      expect(scope).to have_attributes(state: 'reception', case_version: 0)
      expect(scope_of_conv_a.reload.state).to eq('closed')
    end
  end

  describe 'reabertura explícita restaura o atendimento (AC3)' do
    before { conv_a.update!(status: :resolved) }

    it 'open pelo modelo volta o mesmo escopo a active com protocolo e versão' do
      expect { conv_a.update!(status: :open) }
        .to change { scope_of_conv_a.reload.state }.from('closed').to('active')

      expect(scope_of_conv_a).to have_attributes(org_unit_id: org_a.id, case_protocol: 'CASO-A', case_version: 1)
      expect(scope_of_conv_a.closed_at).to be_nil
    end

    it 'toggle_status para open pelo operador com grant reabre (200) e restaura active' do
      post toggle_path, params: { status: 'open' }, headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.status).to eq('open')
      expect(scope_of_conv_a.reload.state).to eq('active')
    end

    it 'com atendimento mais novo do mesmo par, mantém closed e só registra (sem 500)' do
      stub_const('ENV', ENV.to_h.merge('CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                                       'CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))
      fresh = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_a)
      Connecta::Runtime::ReceptionScopeCreator.call(fresh)

      expect { conv_a.update!(status: :open) }.not_to raise_error

      expect(conv_a.reload.status).to eq('open')
      expect(scope_of_conv_a.reload.state).to eq('closed')
    end
  end

  describe 'escrita em conversa resolvida é negada (AC4)' do
    before { conv_a.update!(status: :resolved) }

    it 'operador com grant recebe 403 e nada é gravado' do
      expect do
        post messages_path, params: { content: 'teste', message_type: 'outgoing' }, headers: agent_a.create_new_auth_token
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('resolved')
    end

    it 'administrador nativo também é negado (decisão: resolvida só reabre)' do
      expect do
        post messages_path, params: { content: 'teste do admin', message_type: 'outgoing' },
                            headers: native_admin.create_new_auth_token
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'leitura continua permitida a quem tem grant' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
    end
  end
end
