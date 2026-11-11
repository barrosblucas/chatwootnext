require 'rails_helper'

# Etapa 3 · CSAT pula a pesquisa quando o bot está desativado neste número
# (espelho local contact.custom_attributes['connecta_bot_disabled'] == true).
# Usa as tabelas de produto (connecta_scoped_inboxes / connecta_conversation_scopes).
RSpec.describe 'Connecta Etapa 3 · CSAT pula número com bot desativado' do # rubocop:disable RSpec/DescribeClass
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
      mark_inbox!(inbox)
      scope_for!(conversation, state: 'closed')
    end

    context 'when the bot is disabled for the contact' do
      before do
        contact.update!(custom_attributes: { 'connecta_bot_disabled' => true })
      end

      it 'skips the survey even on final protocol resolution', :aggregate_failures do
        expect(described_class.new(conversation: conversation).perform).to eq(:not_eligible)
        expect(conversation.messages.where(content_type: :input_csat)).to be_empty
      end
    end

    context 'when the bot is enabled for the contact' do
      it 'sends the survey on final protocol resolution' do
        expect { described_class.new(conversation: conversation).perform }
          .to change { conversation.messages.where(content_type: :input_csat).count }.by(1)
      end
    end

    context 'when the inbox is not Connecta-scoped' do
      let(:plain_inbox) { create(:inbox, account: account, csat_survey_enabled: true) }
      let(:plain_conversation) do
        create(:conversation, account: account, inbox: plain_inbox, contact: contact, status: :resolved)
      end

      it 'still skips the survey when the bot is disabled', :aggregate_failures do
        contact.update!(custom_attributes: { 'connecta_bot_disabled' => true })

        expect(described_class.new(conversation: plain_conversation).perform).to eq(:not_eligible)
        expect(plain_conversation.messages.where(content_type: :input_csat)).to be_empty
      end
    end
  end
end
