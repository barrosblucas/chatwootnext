require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_transfer_schema'

# T3.9 (contenção, spike G0): modos `admin_only` e `maintenance` da inbox marcada, sobre o fixture G0 real.
# - admin_only: agente membro da inbox com team_id forçado no dado sintético continua negado em URL, lista, busca,
#   contatos, socket e link de anexo antigo; admin nominal acessa e a abertura fica auditada.
# - maintenance: mensagem recebida é gravada; envio humano responde 409 e o despacho de saída vira parked.
# - enforce: controle positivo curto, o comportamento atual não muda.
# Gate, hooks, socket e download são os reais; nenhuma decisão de autorização é mockada. Só o conector WhatsApp é stubado.
# Specs escritas para a validação consolidada; esta frente não executa rspec.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

# Corpo sintético do anexo canário; conferido nas respostas de download (inclusão e negação).
BODY = 'bytes-sinteticos-g0-t39'.freeze

RSpec.describe 'Connecta G0 · contenção admin_only e maintenance (T3.9)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:search_path) { "/api/v1/accounts/#{account.id}/search" }
  let(:contacts_path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:messages_path) { "#{conversations_path}/#{conv_a.display_id}/messages" }
  let(:download_path) { "/api/v1/accounts/#{account.id}/connecta_attachments/#{attachment.id}/download" }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_admin) { admin_nominal.create_new_auth_token }
  let(:connector) { instance_double(Whatsapp::SendOnWhatsappService, perform: nil) }
  let(:dispatches) { Connecta::Transfer::OutboundDispatchRecord }

  let!(:team_a) { Team.create!(name: 'Equipe A', account: account, allow_auto_assign: false) }
  let!(:message_a) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a,
                     message_type: :outgoing, content: 'contencaoadmin de A')
  end
  let!(:attachment) do
    Attachment.new(account: account, message: message_a, file_type: :file).tap do |record|
      record.file.attach(io: StringIO.new(BODY), filename: 'canario.txt', content_type: 'text/plain')
      record.save!
    end
  end

  before do
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(connector)
    whatsapp_inbox.update!(enable_auto_assignment: false)
    control_inbox.update!(enable_auto_assignment: false)
    contact_a.update!(name: 'Contato Alfa', email: 'alfa@example.com')
    # Dado sintético: agente de equipe ainda vinculado à conversa de A (team_id forçado).
    TeamMember.create!(team: team_a, user: agent_a)
    conv_a.update!(team: team_a)
  end

  after do
    attachment.file.blob.service.delete(attachment.file.blob.key) if attachment.file.attached?
    Current.reset
  end

  # Emite o token do anexo como o hook faz para o usuário, com a epoch viva no banco.
  def issue_token_for(user)
    epoch = Connecta::Scope::UserAuthEpoch.find_by!(user_id: user.id).epoch
    Current.user = user
    Connecta::Scope::AttachmentToken.issue(attachment: attachment, user: user, account: account, epoch: epoch)
  ensure
    Current.reset
  end

  # Dispara o evento e devolve o payload que cada token recebeu nos jobs de broadcast.
  def payloads_by_token
    clear_enqueued_jobs
    yield
    broadcast_jobs = [ActionCableBroadcastJob, Connecta::Scope::AdminMetadataBroadcastJob]
    enqueued_jobs.each_with_object({}) do |job, received|
      next unless broadcast_jobs.include?(job[:job])

      tokens, _event_name, payload = ActiveJob::Arguments.deserialize(job[:args])
      tokens.each { |token| received[token] = payload }
    end
  end

  describe 'admin_only: agente com team_id forçado e membro da inbox' do
    it 'antes da contenção, o agente lê a conversa e a lista (controle da precondição)' do
      get "#{conversations_path}/#{conv_a.display_id}", headers: token_a
      expect(response).to have_http_status(:ok)

      get conversations_path, headers: token_a
      expect(json['data']['payload'].pluck('id')).to include(conv_a.display_id)
    end

    it 'antes da contenção, o anexo emitido para o agente baixa os bytes (controle da precondição do link antigo)' do
      token = issue_token_for(agent_a)

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(BODY)
    end

    context 'with enforcement admin_only' do
      let!(:old_attachment_token) { issue_token_for(agent_a) }

      before { marked_inbox.update!(enforcement: 'admin_only') }

      it '(a) abertura da conversa por URL responde 404 ao agente' do
        get "#{conversations_path}/#{conv_a.display_id}", headers: token_a

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('contencaoadmin de A')
      end

      it '(b) lista não traz a conversa de A ao agente' do
        get conversations_path, headers: token_a

        # Só a conversa da inbox de controle (não marcada, agente é membro na fixture) é visível; conv_a fica de fora.
        expect(json['data']['payload'].pluck('id')).to eq([conv_control.display_id])
        expect(json['data']['meta']['all_count']).to eq(1)
      end

      it '(c) busca não traz a mensagem nem a conversa de A ao agente' do
        get search_path, params: { q: 'contencaoadmin' }, headers: token_a

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['payload']['messages']).to be_empty
        expect(JSON.parse(response.body)['payload']['conversations']).to be_empty
      end

      it '(d) contatos: o agente não vê o contato de A na listagem nem abre o detalhe (404)' do
        get contacts_path, headers: token_a
        expect(json['payload'].pluck('id')).not_to include(contact_a.id)

        get "#{contacts_path}/#{contact_a.id}", headers: token_a
        expect(response).to have_http_status(:not_found)
      end

      it '(e) socket: a mensagem nova não chega ao token do agente, e o admin recebe só metadados' do
        event = Events::Base.new(:'message.created', Time.zone.now, message: message_a)
        received = payloads_by_token { ActionCableListener.instance.message_created(event) }

        expect(received.keys).not_to include(agent_a.pubsub_token)
        expect(received[admin_nominal.pubsub_token]).to include(id: message_a.id, conversation_id: conv_a.display_id)
        expect(received[admin_nominal.pubsub_token].keys).not_to include(:content)
      end

      it '(f) link de anexo emitido antes da contenção responde 404 ao agente e não entrega os bytes' do
        get "#{download_path}?token=#{CGI.escape(old_attachment_token)}", headers: token_a

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(BODY)
      end

      it 'admin nominal abre a conversa (200) e a abertura fica auditada como allow' do
        expect do
          get "#{conversations_path}/#{conv_a.display_id}", headers: token_admin
        end.to change {
          Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, conversation_id: conv_a.id,
                                             access_path: 'detail', decision: 'allow').count
        }.by(1)

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'maintenance: entrada gravada e envio humano bloqueado' do
    context 'with enforcement maintenance' do
      before { marked_inbox.update!(enforcement: 'maintenance') }

      it 'mensagem recebida é gravada na conversa sem perda' do
        incoming = nil
        expect do
          incoming = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: contact_a,
                                      message_type: :incoming, content: 'entrada durante manutencao')
        end.to change(Message, :count).by(1)

        expect(Message.exists?(incoming.id)).to be(true)
        expect(incoming.reload.content).to eq('entrada durante manutencao')
      end

      # Não-admin não passa da leitura (404, decisão 002): o guard de escrita de manutenção (409) só é alcançado por quem lê.
      it 'envio humano do admin nominal responde 409 e nada é gravado; a tentativa fica auditada como negada' do
        expect do
          post messages_path, params: { content: 'nao', message_type: 'outgoing' }, headers: token_admin
        end.not_to change(Message, :count)

        expect(response).to have_http_status(:conflict)
        expect(Connecta::Scope::AccessAudit.where(user_id: admin_nominal.id, decision: 'deny')
                                           .where('access_path LIKE ?', '%_maintenance').count).to eq(1)
      end

      # Manutenção nega leitura de não-admin com 404 (decisão 002:6-8; decisão 003). Admin lê, coberto em admin_only.
      it 'leitura de não-admin responde 404 e a conversa não é revelada' do
        get "#{conversations_path}/#{conv_a.display_id}", headers: token_a

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('contencaoadmin de A')
      end

      it 'job de envio já enfileirado não chama o conector e a linha vira parked' do
        outgoing = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'resposta')

        SendReplyJob.perform_now(outgoing.id)

        expect(connector).not_to have_received(:perform)
        expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('parked')
      end
    end

    context 'with enforcement enforce (controle positivo)' do
      it 'o agente envia mensagem na própria conversa (200) e a mensagem é gravada' do
        expect do
          post messages_path, params: { content: 'olá', message_type: 'outgoing' }, headers: token_a
        end.to change(Message, :count).by(1)

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
