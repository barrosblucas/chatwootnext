require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 parte A (spike G0): dois setores (A e B) na MESMA inbox WhatsApp. Policy, query e HTTP são os reais;
# nenhuma decisão de autorização ou resultado de consulta é mockado. Inbox nativa sem marca serve só de controle.
require_relative 'support/g0_transfer_schema'
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · escopo de conversas (T0.2 parte A)', type: :request do
  include_context 'with connecta g0 scope fixture'

  describe 'lista (GET conversations)' do
    it 'agente A vê o próprio setor, o descendente e o controle nativo, com contagem coerente' do
      get conversations_path, headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_control.display_id)
      expect(json['data']['meta']['all_count']).to eq(3)
    end

    it 'agente B vê só o setor B, sem a conversa de A na mesma inbox' do
      get conversations_path, headers: agent_b.create_new_auth_token

      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_b.display_id)
      expect(json['data']['meta']['all_count']).to eq(1)
    end

    it 'gestor A (acompanhar) vê A e descendentes, mas não B nem o controle nativo' do
      get conversations_path, headers: manager_a.create_new_auth_token

      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_a.display_id, conv_a1.display_id)
      expect(json['data']['meta']['all_count']).to eq(2)
    end

    it 'membro da inbox sem grant não vê nenhuma conversa da inbox marcada' do
      get conversations_path, headers: member_without_grant.create_new_auth_token

      expect(json['data']['payload']).to be_empty
      expect(json['data']['meta']['all_count']).to eq(0)
    end

    it 'admin nominal não recebe conteúdo da inbox marcada na listagem; a listagem fica auditada como metadado' do
      get conversations_path, headers: admin_nominal.create_new_auth_token

      expect(json['data']['payload']).to be_empty
      expect(json['data']['meta']['all_count']).to eq(0)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, access_path: 'list', decision: 'allow').count).to eq(1)
    end

    it 'filtra antes da paginação: com 1 item por página, as páginas trazem só o que o agente pode ver' do
      with_modified_env CONVERSATION_RESULTS_PER_PAGE: '1' do
        pages = (1..3).map do |page|
          get conversations_path, params: { page: page }, headers: agent_a.create_new_auth_token
          JSON.parse(response.body).dig('data', 'payload').pluck('id')
        end

        expect(pages.map(&:size)).to eq([1, 1, 1])
        expect(pages.flatten).to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_control.display_id)
      end
    end

    it 'ignora ator e setor forjados: agente B não ganha A por parâmetro ou cabeçalho' do
      get conversations_path,
          params: { actor_id: agent_a.id, org_unit_id: org_a.id, sector: 'A', user_id: agent_a.id },
          headers: agent_b.create_new_auth_token.merge('X-Connecta-Actor' => agent_a.id.to_s, 'X-Connecta-Org-Unit' => 'A')

      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_b.display_id)
      expect(json['data']['meta']['all_count']).to eq(1)
    end
  end

  describe 'detalhe por URL (GET conversations/:id)' do
    it 'agente A lê a própria conversa' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json['id']).to eq(conv_a.display_id)
    end

    it 'agente B não abre a conversa de A, mesmo na mesma inbox (404: a conversa não é revelada)' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_b.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'gestor A lê descendente de A, mas não o conteúdo de B' do
      get "#{conversations_path}/#{conv_a1.display_id}", headers: manager_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      get "#{conversations_path}/#{conv_b.display_id}", headers: manager_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'membro sem grant não abre nenhuma conversa da inbox marcada' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: member_without_grant.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'admin nominal lê conversa transferida e a leitura fica auditada' do
      get "#{conversations_path}/#{conv_transferred.display_id}", headers: admin_nominal.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_transferred.id,
                                                access_path: 'detail', decision: 'allow').count).to eq(1)
    end

    it 'controle nativo: inbox não marcada segue a regra nativa (membro lê, não membro não lê)' do
      get "#{conversations_path}/#{conv_control.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      get "#{conversations_path}/#{conv_control.display_id}", headers: agent_b.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'política real (ConversationPolicy#show?) sem mock' do
    def policy_for(user)
      ConversationPolicy.new({ user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }, conv_a)
    end

    it 'decide por grant e escopo, não por papel de agente nativo' do
      expect(policy_for(agent_a).show?).to be(true)
      expect(policy_for(manager_a).show?).to be(true)
      expect(policy_for(agent_b).show?).to be(false)
      expect(policy_for(member_without_grant).show?).to be(false)
    end
  end

  describe 'estados e fail-closed' do
    it 'escopo ausente na inbox marcada só é lido pelo admin nominal' do
      get "#{conversations_path}/#{conv_orphan.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get "#{conversations_path}/#{conv_orphan.display_id}", headers: admin_nominal.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it 'estado transferred_out não dá acesso ao agente com grant' do
      get "#{conversations_path}/#{conv_transferred.display_id}", headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'transferring permite leitura, mas bloqueia envio de mensagem' do
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'transferring')

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'bloqueado', message_type: 'outgoing' },
                                                                    headers: agent_a.create_new_auth_token
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'inbox em admin_only nega agentes e mantém o admin nominal' do
      marked_inbox.update!(enforcement: 'admin_only')

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get "#{conversations_path}/#{conv_a.display_id}", headers: admin_nominal.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it 'manutenção da inbox nega não-admin (a inbox não marcada do agente continua nativa)' do
      marked_inbox.update!(maintenance: true)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'heartbeat além da graça nega não-admin na lista e no detalhe' do
      projection_heartbeat.update!(last_heartbeat_at: 30.minutes.ago)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get "#{conversations_path}/#{conv_transferred.display_id}", headers: admin_nominal.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it 'heartbeat dentro da janela de graça mantém a leitura do último grant aplicado' do
      projection_heartbeat.update!(last_heartbeat_at: 5.minutes.ago)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_control.display_id)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)
    end

    it 'usuário revogado continua negado mesmo dentro da janela de graça' do
      projection_heartbeat.update!(last_heartbeat_at: 5.minutes.ago)
      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(revoked_locally_at: Time.current)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'graça zerada desliga o fail-open (fail-closed direto no TTL)' do
      with_modified_env CONNECTA_ACL_STALE_GRACE_SEC: '0' do
        projection_heartbeat.update!(last_heartbeat_at: 5.minutes.ago)

        get conversations_path, headers: agent_a.create_new_auth_token
        expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)
      end
    end

    it 'revogação local vale na requisição seguinte, sem cache' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:ok)

      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(revoked_locally_at: Time.current)

      get "#{conversations_path}/#{conv_a.display_id}", headers: agent_a.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      get conversations_path, headers: agent_a.create_new_auth_token
      expect(json['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)
    end
  end

  describe 'escrita (gestor sem escrita; agente com grant escreve)' do
    it 'agente A envia mensagem na própria conversa' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'olá', message_type: 'outgoing' },
                                                                    headers: agent_a.create_new_auth_token
      end.to change(Message, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it 'gestor A não envia mensagem e a tentativa fica negada na auditoria' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'nao', message_type: 'outgoing' },
                                                                    headers: manager_a.create_new_auth_token
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:forbidden)
      expect(Connecta::Scope::AccessAudit.where(user_id: manager_a.id, access_path: 'message_create', decision: 'deny').count).to eq(1)
    end

    it 'agente B não envia mensagem na conversa de A (404: a conversa não é revelada)' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages", params: { content: 'nao', message_type: 'outgoing' },
                                                                    headers: agent_b.create_new_auth_token
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'gestor A não encerra a conversa' do
      post "#{conversations_path}/#{conv_a.display_id}/toggle_status", params: { status: 'resolved' },
                                                                       headers: manager_a.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.status).to eq('open')
    end

    it 'agente A encerra a própria conversa na etapa ativa' do
      post "#{conversations_path}/#{conv_a.display_id}/toggle_status", params: { status: 'resolved' },
                                                                       headers: agent_a.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(conv_a.reload.status).to eq('resolved')
    end

    it 'gestor A não atribui a conversa a outro agente' do
      post "#{conversations_path}/#{conv_a.display_id}/assignments", params: { assignee_id: agent_a.id },
                                                                     headers: manager_a.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(conv_a.reload.assignee_id).to be_nil
    end

    it 'controle nativo: agente membro segue enviando mensagem na inbox não marcada' do
      expect do
        post "#{conversations_path}/#{conv_control.display_id}/messages",
             params: { content: 'controle', message_type: 'outgoing' },
             headers: agent_a.create_new_auth_token
      end.to change(Message, :count).by(1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'administrador nativo da conta (I.1a: full same-account sem grant setorial)' do
    let!(:native_admin) { create(:user, account: account, role: :administrator) }
    let(:token_native) { native_admin.create_new_auth_token }

    let!(:other_account) { create(:account) }
    let!(:other_channel) do
      build(:channel_whatsapp, account: other_account, provider: 'baileys').tap { |channel| channel.save!(validate: false) }
    end
    let!(:other_inbox) do
      build(:inbox, account: other_account, channel: other_channel, name: 'WhatsApp Outra').tap { |inbox| inbox.save!(validate: false) }
    end
    let!(:other_contact) { create(:contact, account: other_account) }
    let!(:other_conv) { create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact) }
    let!(:dual_admin) do
      create(:user, account: account, role: :administrator).tap do |user|
        create(:account_user, user: user, account: other_account, role: :agent)
        create(:inbox_member, inbox: other_inbox, user: user)
      end
    end
    let(:token_dual) { dual_admin.create_new_auth_token }
    let(:other_path) { "/api/v1/accounts/#{other_account.id}/conversations" }

    before do
      Connecta::Scope::ScopedInbox.create!(inbox_id: other_inbox.id, enforcement: 'enforce', maintenance: false)
      Connecta::Scope::ConversationScope.create!(conversation_id: other_conv.id, inbox_id: other_inbox.id, contact_id: other_contact.id,
                                                 org_unit: org_a, state: 'active', case_protocol: 'CASO-X', case_version: 1)
    end

    it 'nativo sem grant setorial lista todas as conversas da conta, com auditoria de metadado' do
      get conversations_path, headers: token_native

      expect(response).to have_http_status(:ok)
      expect(json['data']['payload'].pluck('id'))
        .to contain_exactly(conv_a.display_id, conv_a1.display_id, conv_b.display_id,
                            conv_transferred.display_id, conv_orphan.display_id, conv_control.display_id)
      expect(json['data']['meta']['all_count']).to eq(6)
      expect(Connecta::Scope::AccessAudit.where(user_id: native_admin.id, access_path: 'list', decision: 'allow').count).to eq(1)
    end

    it 'nativo lê qualquer setor da conta, com leitura auditada por conversa' do
      get "#{conversations_path}/#{conv_b.display_id}", headers: token_native

      expect(response).to have_http_status(:ok)
      expect(Connecta::Scope::AccessAudit.where(user_id: native_admin.id, conversation_id: conv_b.id,
                                                access_path: 'detail', decision: 'allow').count).to eq(1)
    end

    it 'nativo envia transcrição da conversa marcada por e-mail, com allow auditado' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/transcript", params: { email: 'nativo@example.com' }, headers: token_native
      end.to have_enqueued_mail(ConversationReplyMailer, :conversation_transcript)

      expect(response).to have_http_status(:ok)
      expect(Connecta::Scope::AccessAudit.where(user_id: native_admin.id, conversation_id: conv_a.id, access_path: 'conversation_transcript',
                                                decision: 'allow').count).to eq(1)
    end

    it 'nativo escreve na conversa de outro setor pelo endpoint real' do
      expect do
        post "#{conversations_path}/#{conv_b.display_id}/messages", params: { content: 'olá do nativo', message_type: 'outgoing' },
                                                                    headers: token_native
      end.to change(Message, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it 'admin nominal continua só leitura: escrita nega com 403 e audita deny' do
      expect do
        post "#{conversations_path}/#{conv_a.display_id}/messages",
             params: { content: 'nao', message_type: 'outgoing' }, headers: admin_nominal.create_new_auth_token
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:forbidden)
      expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_a.id,
                                                access_path: 'message_create', decision: 'deny').count).to eq(1)
    end

    it 'admin da conta A como agent na B não é full na B: lista e detalhe negam' do
      get other_path, headers: token_dual

      expect(json['data']['payload']).to be_empty

      get "#{other_path}/#{other_conv.display_id}", headers: token_dual
      expect(response).to have_http_status(:not_found)
    end

    it 'recurso de outra conta nega no Gate mesmo com admin na conta A, com auditoria deny' do
      expect(
        Connecta::Scope::Gate.new(dual_admin).read?(other_conv, access_path: 'detail')
      ).to be(false)
      expect(Connecta::Scope::AccessAudit.where(user_id: dual_admin.id, conversation_id: other_conv.id,
                                                access_path: 'detail', decision: 'deny').count).to eq(1)
    end

    it 'rebaixamento para agent na mesma instância tira o full sem privilégio residual' do
      get "#{conversations_path}/#{conv_b.display_id}", headers: token_dual
      expect(response).to have_http_status(:ok)

      AccountUser.find_by!(account_id: account.id, user_id: dual_admin.id).update!(role: :agent)

      get "#{conversations_path}/#{conv_b.display_id}", headers: token_dual
      expect(response).to have_http_status(:not_found)

      get conversations_path, headers: token_dual
      expect(json['data']['payload']).to be_empty
    end

    it 'remoção do vínculo com a conta tira o full: nativo nega antes do Gate, sem privilégio residual' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: token_native
      expect(response).to have_http_status(:ok)
      audits_before_removal = Connecta::Scope::AccessAudit.where(user_id: native_admin.id).count

      AccountUser.find_by!(account_id: account.id, user_id: native_admin.id).destroy!

      get "#{conversations_path}/#{conv_a.display_id}", headers: token_native
      expect(response).to have_http_status(:unauthorized)
      expect(Connecta::Scope::AccessAudit.where(user_id: native_admin.id).count).to eq(audits_before_removal)
    end
  end

  describe 'transferência do admin nativo (I.1b: policy + transação G0)' do
    let!(:native_admin) { create(:user, account: account, role: :administrator) }
    let(:token_native) { native_admin.create_new_auth_token }
    let!(:other_inbox) { create(:inbox, account: other_account) }
    let!(:other_account) { create(:account) }
    let!(:dual_admin) do
      create(:user, account: account, role: :administrator).tap do |user|
        create(:account_user, user: user, account: other_account, role: :agent)
      end
    end
    let(:sent) { [] }
    let(:client) do
      recipient = sent
      stub = Object.new
      stub.define_singleton_method(:get) do |path|
        recipient << { method: :get, path: path }
        { 'destinations' => [] }
      end
      stub.define_singleton_method(:post) do |_path, payload|
        recipient << { method: :post, path: payload[:destination_org_unit_id], payload: payload }
        { 'case_version' => 1, 'to_session_ref' => 'sess-2' }
      end
      stub
    end
    let(:summary) { { 'subject' => 'Segunda via', 'completed' => 'Dados conferidos', 'next_action' => 'Retorno do setor B' } }
    let(:local_transfer) { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b) }
    let(:origin_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }

    before do
      Connecta::Transfer::Installer.install!
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s, 'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                                       'CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))
      allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
      allow(Connecta::Runtime::TransferCommitJob).to receive(:perform_later)
      allow(Connecta::Runtime::TransferAbortJob).to receive(:perform_later)
    end

    it 'policy autoriza nativo listar destinos pela rota real' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/connecta_transfer/destinations",
          headers: token_native

      expect(response).to have_http_status(:ok)
      call = sent.find { |entry| entry[:path].to_s.start_with?('/attendance/v1/transfer-destinations') }
      query = URI.decode_www_form(URI(call[:path]).query.to_s).to_h
      expect(query).to include('account_id' => account.id.to_s, 'actor_chatwoot_user_id' => native_admin.id.to_s)
    end

    it 'policy autoriza nativo A→B sem grant; transação real comete destino ativo' do
      expect(local_transfer.begin!).to eq(:proceed)
      destination = local_transfer.commit_local!(
        target_case_version: 2, summary: "#{summary['subject']} #{summary['completed']} #{summary['next_action']}"
      )

      expect(destination).to be_a(Conversation)
      expect(origin_scope.reload.state).to eq('transferred_out')
      expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: destination.id))
        .to have_attributes(state: 'pending_activation', org_unit_id: org_b.id)
    end

    it 'transação nega destino da mesma unidade e unidade inexistente' do
      same_unit = Connecta::Runtime::TransferTransaction.new(
        account_id: account.id, conversation: conv_b, actor: native_admin,
        destination_org_unit_id: org_b.id, summary: summary
      )
      expect { same_unit.call }.to raise_error(Connecta::Runtime::TransferTransaction::Error)

      invalid_unit = Connecta::Runtime::TransferTransaction.new(
        account_id: account.id, conversation: conv_b, actor: native_admin,
        destination_org_unit_id: 0, summary: summary
      )
      expect { invalid_unit.call }.to raise_error(Connecta::Runtime::TransferTransaction::Error)
    end

    it 'agent sem grant transferir continua negado pela Policy' do
      expect do
        Connecta::Runtime::TransferPolicy.new(conversation: conv_b, actor: agent_a).authorize!
      end.to raise_error(Connecta::Runtime::TransferTransaction::Error)
    end

    it 'cross-account: nativo da A não autoriza conversa da B (admin B decide)' do
      dual = create(:user, account: account, role: :administrator)
      create(:account_user, user: dual, account: other_account, role: :agent)
      other_contact_b = create(:contact, account: other_account)
      other_conv_b = create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact_b)
      other_scope = Connecta::Scope::ConversationScope.create!(
        conversation_id: other_conv_b.id, inbox_id: other_inbox.id, contact_id: other_contact_b.id,
        org_unit: org_a, state: 'active', case_protocol: 'CASO-X', case_version: 1
      )

      expect do
        Connecta::Runtime::TransferPolicy.new(conversation: other_conv_b, actor: dual).authorize!
      end.to raise_error(Connecta::Runtime::TransferTransaction::Error)
      expect(Connecta::Scope::ConversationScope.find(other_scope.id).state).to eq('active')
    end

    it 'rebaixamento de admin para agent tira a permissão de transferir na mesma sessão' do
      expect(Connecta::Runtime::TransferPolicy.new(conversation: conv_b, actor: dual_admin).authorize!).not_to be_nil

      AccountUser.find_by!(account_id: account.id, user_id: dual_admin.id).update!(role: :agent)

      expect do
        Connecta::Runtime::TransferPolicy.new(conversation: conv_b, actor: dual_admin).authorize!
      end.to raise_error(Connecta::Runtime::TransferTransaction::Error)
    end

    it 'can_transfer do escopo: nativo true, agente sem transferir false' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/connecta_scope", headers: token_native
      expect(JSON.parse(response.body)['can_transfer']).to be(true)

      get "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/connecta_scope",
          headers: agent_a.create_new_auth_token
      expect(JSON.parse(response.body)['can_transfer']).to be(false)
    end
  end

  describe 'esquema do protótipo' do
    it 'índices: um escopo por conversa; um escopo não terminal por contato na inbox; estado terminal libera o contato' do
      # Savepoint: a violação do índice não pode abortar a transação do exemplo.
      expect do
        Connecta::Scope::ConversationScope.transaction(requires_new: true) do
          Connecta::Scope::ConversationScope.create!(conversation_id: conv_orphan.id, inbox_id: whatsapp_inbox.id,
                                                     contact_id: contact_a.id, org_unit: org_a, state: 'reception')
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)

      expect do
        Connecta::Scope::ConversationScope.transaction(requires_new: true) do
          Connecta::Scope::ConversationScope.create!(conversation_id: conv_a.id, inbox_id: whatsapp_inbox.id,
                                                     contact_id: contact_b.id, org_unit: org_a, state: 'reception')
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)

      Connecta::Scope::ConversationScope.create!(conversation_id: conv_orphan.id, inbox_id: whatsapp_inbox.id,
                                                 contact_id: contact_a.id, org_unit: org_a, state: 'transferred_out')
      expect(Connecta::Scope::ConversationScope.where(contact_id: contact_a.id).count).to eq(2)
    end

    it 'registro de auditoria é append-only' do
      audit = Connecta::Scope::AccessAudit.create!(user_id: agent_a.id, conversation_id: conv_a.id, surface: 'conversation',
                                                   access_path: 'detail', decision: 'allow', created_at: Time.current)

      expect { audit.update!(decision: 'deny') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
