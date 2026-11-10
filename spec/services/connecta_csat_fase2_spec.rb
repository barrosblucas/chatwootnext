require 'rails_helper'

# Fase 2 · CSAT com protocolo (AC1/AC2) e bloqueio de senha (AC3).
# Usa as tabelas de produto (connecta_scoped_inboxes / connecta_conversation_scopes),
# sem o ambiente especial G0: os hooks de ciclo de vida não estão instalados aqui,
# então os escopos são criados direto no estado desejado.
RSpec.describe 'Connecta Fase 2 · CSAT com protocolo e senha gerenciada' do
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
    before do
      allow(Conversations::MessageWindowService).to receive(:new).and_return(double(can_reply?: true))
    end

    context 'em inbox marcada' do
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

    context 'em inbox não marcada' do
      it 'mantém o comportamento nativo' do
        expect(described_class.new(conversation: conversation).perform).not_to eq(:not_eligible)
      end
    end
  end

  describe 'texto da pesquisa com protocolo' do
    before do
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed', protocol: 'BND00000042')
      allow(Conversations::MessageWindowService).to receive(:new).and_return(double(can_reply?: true))
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
                                         content_attributes: {
                                           'submitted_values' => { 'csat_survey_response' => { 'rating' => 3 } }
                                         })

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
    around do |example|
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s))
      example.run
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
      super_admin.update_column(:type, 'SuperAdmin')

      expect(described_class.managed?(super_admin)).to be(false)
    end

    it 'não gerenciado: agent de outra conta' do
      other = create(:account)
      user = create(:user, account: other, role: :agent)

      expect(described_class.managed?(user)).to be(false)
    end
  end

  describe 'bloqueio de troca de senha (AC3)' do
    around do |example|
      stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s))
      example.run
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
end
