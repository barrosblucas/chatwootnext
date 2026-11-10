require 'rails_helper'

# Fase 2 · CSAT com protocolo (AC1/AC2) e bloqueio de senha (AC3).
# Usa as tabelas de produto (connecta_scoped_inboxes / connecta_conversation_scopes),
# sem o ambiente especial G0: os hooks de ciclo de vida não estão instalados aqui,
# então os escopos são criados direto no estado desejado.
RSpec.describe 'Connecta Fase 2 · CSAT com protocolo e senha gerenciada' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, csat_survey_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact,
                          contact_inbox: contact_inbox, status: :resolved)
  end

  def mark_inbox!(target_inbox)
    Connecta::ScopedInbox.create!(inbox_id: target_inbox.id)
  end

  def scope_for!(target_conversation, state:, protocol: 'BND00000001')
    org = Connecta::OrgUnit.create!(name: "Setor #{SecureRandom.hex(4)}", path: "/s/#{SecureRandom.hex(6)}")
    Connecta::ConversationScope.create!(
      conversation_id: target_conversation.id, inbox_id: target_conversation.inbox_id,
      contact_id: target_conversation.contact_id, org_unit_id: org.id,
      state: state, case_protocol: protocol
    )
  end

  describe CsatSurveyService do
    let(:open_window) { instance_double(Conversations::MessageWindowService, can_reply?: true) }

    before do
      allow(Conversations::MessageWindowService).to receive(:new).and_return(open_window)
    end

    context 'when the inbox is marked' do
      before { mark_inbox!(inbox) }

      it 'envia na resolução final do protocolo (escopo closed com protocolo)' do
        scope_for!(conversation, state: 'closed')

        expect { described_class.new(conversation: conversation).perform }
          .to change { conversation.messages.where(content_type: :input_csat).count }.by(1)
      end

      it 'envia quando o hook de resolução ainda não fechou o escopo (corrida after_commit)' do
        scope_for!(conversation, state: 'active')

        expect(described_class.new(conversation: conversation).perform).not_to eq(:not_eligible)
      end

      it 'não envia para origem de transferência (transferred_out)' do
        scope_for!(conversation, state: 'transferred_out')

        expect(described_class.new(conversation: conversation).perform).to eq(:not_eligible)
      end

      it 'não envia sem escopo (só triagem, sem protocolo)' do
        expect(described_class.new(conversation: conversation).perform).to eq(:not_eligible)
      end

      it 'não envia com escopo sem protocolo' do
        scope_for!(conversation, state: 'closed', protocol: nil)

        expect(described_class.new(conversation: conversation).perform).to eq(:not_eligible)
      end
    end

    context 'when the inbox is not marked' do
      it 'mantém o comportamento nativo' do
        expect(described_class.new(conversation: conversation).perform).not_to eq(:not_eligible)
      end
    end
  end

  describe 'texto da pesquisa com protocolo' do
    let(:open_window) { instance_double(Conversations::MessageWindowService, can_reply?: true) }

    before do
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed', protocol: 'BND00000042')
      allow(Conversations::MessageWindowService).to receive(:new).and_return(open_window)
    end

    it 'usa o padrão pt-BR com o protocolo quando a inbox não configura mensagem' do
      message = MessageTemplates::Template::CsatSurvey.new(conversation: conversation).perform

      expect(message.content).to include('BND00000042')
      expect(message.content).to start_with('✅ Seu atendimento do protocolo')
    end

    it 'honra csat_config.message com {{protocolo}}' do
      inbox.update!(csat_config: { 'message' => 'Atendimento {{protocolo}} finalizado. Nota?' })

      message = MessageTemplates::Template::CsatSurvey.new(conversation: conversation).perform

      expect(message.content).to eq('Atendimento BND00000042 finalizado. Nota?')
    end

    it 'anexa o link público ao texto do protocolo na renderização' do
      api_inbox = create(:inbox, account: account, channel: create(:channel_api, account: account),
                                 csat_survey_enabled: true)
      mark_inbox!(api_inbox)
      api_conversation = create(:conversation, account: account, inbox: api_inbox, status: :resolved)
      scope_for!(api_conversation, state: 'closed', protocol: 'BND00000077')
      csat_message = create(:message, conversation: api_conversation, inbox: api_inbox, account: account,
                                      message_type: :outgoing, content_type: :input_csat, content: 'x')

      rendered = MessageContentPresenter.new(csat_message).outgoing_content

      expect(rendered).to include('BND00000077')
      expect(rendered).to include("/survey/responses/#{api_conversation.uuid}")
    end
  end

  describe CsatSurveys::ResponseBuilder do
    let(:csat_message) do
      create(:message, conversation: conversation, inbox: inbox, account: account,
                       message_type: :outgoing, content_type: :input_csat,
                       content_attributes: { 'submitted_values' => { 'csat_survey_response' => { 'rating' => 4 } } })
    end

    before do
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed')
    end

    it 'descarta o comentário com disable_feedback e empurra a nota ao WP' do
      inbox.update!(csat_config: { 'disable_feedback' => true })
      csat_message.content_attributes = {
        'submitted_values' => { 'csat_survey_response' => { 'rating' => 5, 'feedback_message' => 'ótimo' } }
      }

      built = nil
      expect { built = described_class.new(message: csat_message).perform }
        .to have_enqueued_job(Connecta::Runtime::CsatPushJob)

      expect(built.feedback_message).to be_nil
      expect(built.rating).to eq(5)
    end

    it 'mantém o comentário sem a flag e empurra a nota ao WP' do
      csat_message.content_attributes = {
        'submitted_values' => { 'csat_survey_response' => { 'rating' => 5, 'feedback_message' => 'ótimo' } }
      }

      built = nil
      expect { built = described_class.new(message: csat_message).perform }
        .to have_enqueued_job(Connecta::Runtime::CsatPushJob)

      expect(built.feedback_message).to eq('ótimo')
    end

    it 'não empurra ao WP fora do enforcement' do
      other = create(:inbox, account: account, csat_survey_enabled: true)
      other_conversation = create(:conversation, account: account, inbox: other, status: :resolved)
      other_message = create(:message, conversation: other_conversation, inbox: other, account: account,
                                       message_type: :outgoing, content_type: :input_csat,
                                       content_attributes: { 'submitted_values' => { 'csat_survey_response' => { 'rating' => 3 } } })

      expect { described_class.new(message: other_message).perform }
        .not_to have_enqueued_job(Connecta::Runtime::CsatPushJob)
    end
  end

  describe Connecta::Runtime::CsatPushJob do
    it 'posta o contrato exato, sem PII nem comentário' do
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed', protocol: 'BND00000099')
      response = create(:csat_survey_response, account: account, conversation: conversation,
                                               contact: contact, rating: 4)
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s,
                                       'CONNECTA_PLATFORM_URL' => 'https://wp.example',
                                       'CONNECTA_FORK_TO_PLATFORM_SECRET' => 's3cret'))
      client = instance_double(Connecta::Runtime::PlatformClient)
      allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
      posted = nil
      allow(client).to receive(:post) { |path, payload| posted = [path, payload] }

      described_class.new.perform(response.id)

      expect(posted[0]).to eq('/attendance/v1/csat')
      expect(posted[1]).to include(
        account_id: account.id,
        conversation_id: conversation.display_id,
        case_protocol: 'BND00000099',
        rating: 4,
        responded_at: response.reload.updated_at.iso8601,
        csat_response_id: response.id
      )
      expect(posted[1].keys).to match_array(
        %i[account_id conversation_id case_protocol rating responded_at csat_response_id]
      )
    end
  end

  describe Connecta::Runtime::PasswordGuard do
    before do
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s))
    end

    it 'gerenciado: agent da conta Connecta sem privilégio' do
      agent = create(:user, account: account, role: :agent)

      expect(described_class.managed?(agent)).to be(true)
    end

    it 'não gerenciado: administrator da conta Connecta' do
      admin = create(:user, account: account, role: :administrator)

      expect(described_class.managed?(admin)).to be(false)
    end

    it 'não gerenciado: administrator em outra conta' do
      other = create(:account)
      user = create(:user, account: account, role: :agent)
      create(:account_user, user: user, account: other, role: :administrator)

      expect(described_class.managed?(user)).to be(false)
    end

    it 'não gerenciado: SuperAdmin' do
      super_admin = create(:user, account: account, role: :agent)
      super_admin.update!(type: 'SuperAdmin')

      expect(described_class.managed?(super_admin)).to be(false)
    end

    it 'não gerenciado: agent de outra conta' do
      other = create(:account)
      user = create(:user, account: other, role: :agent)

      expect(described_class.managed?(user)).to be(false)
    end
  end

  describe 'bloqueio de troca de senha (AC3)', type: :request do
    before do
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s))
    end

    let!(:managed) { create(:user, account: account, role: :agent) }

    it 'POST /auth/password responde 200 uniforme sem enviar reset ao gerenciado' do
      expect do
        post user_password_path, params: { email: managed.email, redirect_url: 'http://test.host' }, as: :json
      end.not_to(change { managed.reload.reset_password_token })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['message']).to eq(I18n.t('messages.reset_password'))
    end

    it 'POST /auth/password envia reset ao não gerenciado (controle)' do
      regular = create(:user, account: create(:account), role: :agent)

      expect do
        post user_password_path, params: { email: regular.email, redirect_url: 'http://test.host' }, as: :json
      end.to(change { regular.reload.reset_password_token })

      expect(response).to have_http_status(:ok)
    end

    it 'PUT /auth/password com token devolve 422 ao gerenciado' do
      raw = managed.send(:set_reset_password_token)

      put user_password_path,
          params: { reset_password_token: raw, password: 'NovaSenha1!', password_confirmation: 'NovaSenha1!' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq(Connecta::Runtime::PasswordGuard::MANAGED_MESSAGE)
    end

    it 'PUT /api/v1/profile com senha devolve 422 com código ao gerenciado' do
      put '/api/v1/profile',
          params: { profile: { current_password: 'Password1!', password: 'NovaSenha1!',
                               password_confirmation: 'NovaSenha1!' } },
          headers: managed.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('password_managed_by_facilita')
      expect(response.parsed_body['message']).to eq(Connecta::Runtime::PasswordGuard::MANAGED_MESSAGE)
    end

    it 'PUT /api/v1/profile com senha segue liberado ao administrator (controle)' do
      admin = create(:user, account: account, role: :administrator)

      put '/api/v1/profile',
          params: { profile: { current_password: 'Password1!', password: 'NovaSenha2!',
                               password_confirmation: 'NovaSenha2!' } },
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'claim da pesquisa em escopo closed (Fase 2 · entrega crítica)' do
    let(:record_for) do
      ->(message) { Connecta::Transfer::OutboundDispatchRecord.find_by!(message_id: message.id) }
    end

    def claimable_message!(target_conversation, content_type: :input_csat, message_type: :outgoing)
      create(:message, conversation: target_conversation, inbox: target_conversation.inbox,
                       account: target_conversation.account, message_type: message_type,
                       content_type: content_type, content: 'x')
    end

    before { mark_inbox!(inbox) }

    it 'pesquisa final (closed + protocolo, input_csat) despacha' do
      scope_for!(conversation, state: 'closed', protocol: 'BND00000111')
      message = claimable_message!(conversation)

      Connecta::Transfer::OutboundDispatch.enqueue!(message)

      expect(Connecta::Transfer::OutboundDispatch.claim!(message)).to be(true)
      expect(record_for.call(message).state).to eq('dispatching')
    end

    it 'outra saída em escopo closed continua estacionada' do
      scope_for!(conversation, state: 'closed', protocol: 'BND00000111')
      message = claimable_message!(conversation, content_type: :text)

      Connecta::Transfer::OutboundDispatch.enqueue!(message)

      expect(Connecta::Transfer::OutboundDispatch.claim!(message)).to be(false)
      expect(record_for.call(message).state).to eq('parked')
    end

    it 'pesquisa sem protocolo em closed continua estacionada' do
      scope_for!(conversation, state: 'closed', protocol: nil)
      message = claimable_message!(conversation)

      Connecta::Transfer::OutboundDispatch.enqueue!(message)

      expect(Connecta::Transfer::OutboundDispatch.claim!(message)).to be(false)
      expect(record_for.call(message).state).to eq('parked')
    end

    it 'pesquisa de origem de transferência (transferred_out) continua estacionada' do
      scope_for!(conversation, state: 'transferred_out', protocol: 'BND00000111')
      message = claimable_message!(conversation)

      Connecta::Transfer::OutboundDispatch.enqueue!(message)

      expect(Connecta::Transfer::OutboundDispatch.claim!(message)).to be(false)
      expect(record_for.call(message).state).to eq('parked')
    end

    it 'saída comum em escopo active despacha (controle nativo)' do
      scope_for!(conversation, state: 'active', protocol: 'BND00000111')
      message = claimable_message!(conversation, content_type: :text)

      Connecta::Transfer::OutboundDispatch.enqueue!(message)

      expect(Connecta::Transfer::OutboundDispatch.claim!(message)).to be(true)
      expect(record_for.call(message).state).to eq('dispatching')
    end

    it 'avisa o WP (csat/sent) quando a pesquisa é aceita' do
      scope_for!(conversation, state: 'closed', protocol: 'BND00000111')
      message = claimable_message!(conversation)
      Connecta::Transfer::OutboundDispatch.enqueue!(message)
      expect(Connecta::Transfer::OutboundDispatch.claim!(message)).to be(true)

      expect { Connecta::Transfer::OutboundDispatch.resolve!(message, 'accepted') }
        .to have_enqueued_job(Connecta::Runtime::CsatSentJob).with(message.id)
    end

    it 'não avisa o WP quando a saída comum é aceita' do
      scope_for!(conversation, state: 'active', protocol: 'BND00000111')
      message = claimable_message!(conversation, content_type: :text)
      Connecta::Transfer::OutboundDispatch.enqueue!(message)
      expect(Connecta::Transfer::OutboundDispatch.claim!(message)).to be(true)

      expect { Connecta::Transfer::OutboundDispatch.resolve!(message, 'accepted') }
        .not_to have_enqueued_job(Connecta::Runtime::CsatSentJob)
    end
  end

  describe Connecta::Runtime::CsatSentJob do
    it 'posta o contrato exato do aviso de envio, sem telefone/nome' do
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed', protocol: 'BND00000222')
      inbox.update!(csat_config: { 'mode' => 'whatsapp', 'window_minutes' => 30 })
      message = create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :outgoing, content_type: :input_csat, content: 'x')
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s,
                                       'CONNECTA_PLATFORM_URL' => 'https://wp.example',
                                       'CONNECTA_FORK_TO_PLATFORM_SECRET' => 's3cret'))
      client = instance_double(Connecta::Runtime::PlatformClient)
      allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
      posted = nil
      allow(client).to receive(:post) { |path, payload| posted = [path, payload] }

      described_class.new.perform(message.id)

      expect(posted[0]).to eq('/attendance/v1/csat/sent')
      expect(posted[1]).to include(
        account_id: account.id,
        conversation_id: conversation.display_id,
        case_protocol: 'BND00000222',
        survey_uuid: conversation.uuid,
        contact_id: conversation.contact_id,
        mode: 'whatsapp',
        sent_at: message.reload.created_at.iso8601
      )
      expect(posted[1].keys).to match_array(
        %i[account_id conversation_id case_protocol survey_uuid contact_id mode sent_at]
      )
    end
  end

  describe 'modo whatsapp: texto sem link' do
    before do
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed', protocol: 'BND00000333')
      inbox.update!(csat_config: { 'mode' => 'whatsapp' })
    end

    it 'survey_message usa o texto de resposta na conversa com o protocolo' do
      text = Connecta::Scope::CsatPolicy.survey_message(conversation)

      expect(text).to include('BND00000333')
      expect(text).to include('nota de *1 a 5*')
      expect(text).not_to include('survey/responses')
    end

    it 'presenter não anexa link no modo whatsapp' do
      api_inbox = create(:inbox, account: account, channel: create(:channel_api, account: account),
                                 csat_survey_enabled: true, csat_config: { 'mode' => 'whatsapp' })
      mark_inbox!(api_inbox)
      api_conversation = create(:conversation, account: account, inbox: api_inbox, status: :resolved)
      scope_for!(api_conversation, state: 'closed', protocol: 'BND00000344')
      csat_message = create(:message, conversation: api_conversation, inbox: api_inbox, account: account,
                                      message_type: :outgoing, content_type: :input_csat, content: 'x')

      rendered = MessageContentPresenter.new(csat_message).outgoing_content

      expect(rendered).to include('BND00000344')
      expect(rendered).not_to include("/survey/responses/#{api_conversation.uuid}")
    end

    it 'modo link mantém texto do protocolo (controle)' do
      inbox.update!(csat_config: { 'mode' => 'link' })
      link_text = Connecta::Scope::CsatPolicy.survey_message(conversation)

      expect(link_text).to start_with('✅ Seu atendimento do protocolo')
      expect(link_text).to include('BND00000333')
    end
  end

  describe 'nota digitada no WhatsApp via endpoint público (modo whatsapp)', type: :request do
    it 'aceita a nota sem comentário e o builder empurra a nota ao WP' do
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed', protocol: 'BND00000444')
      inbox.update!(csat_config: { 'mode' => 'whatsapp', 'disable_feedback' => true })
      message = create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :outgoing, content_type: :input_csat, content: 'x')

      patch "/public/api/v1/csat_survey/#{conversation.uuid}",
            params: { message: { submitted_values: { csat_survey_response: { rating: 5 } } } }, as: :json

      expect(response).to have_http_status(:success)

      # O dispatcher do listener é assíncrono (EventDispatcherJob): roda o
      # builder aqui como o listener faria após o PUT.
      built = nil
      expect { built = CsatSurveys::ResponseBuilder.new(message: message.reload).perform }
        .to have_enqueued_job(Connecta::Runtime::CsatPushJob)

      expect(built.rating).to eq(5)
      expect(built.feedback_message).to be_nil
    end
  end
end
