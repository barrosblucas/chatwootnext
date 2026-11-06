require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

RSpec.describe 'Connecta Baileys agent signature (S.1a)' do # rubocop:disable RSpec/DescribeClass
  subject(:built_message) { Messages::MessageBuilder.new(user, conversation, params).perform }

  let(:account) { create(:account) }
  let(:user) do
    create(
      :user,
      account: account,
      name: 'Agente Ficticio',
      display_name: 'Agente Ficticio',
      email: 'agente.ficticio@example.test'
    )
  end
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:params) do
    ActionController::Parameters.new({ content: 'Olá, como posso ajudar?' })
  end

  describe 'Baileys inbox' do
    let(:baileys_channel) do
      create(
        :channel_whatsapp, account: account, provider: 'baileys',
                           provider_config: { webhook_verify_token: 'synthetic-token' },
                           validate_provider_config: false, received_messages: false
      )
    end
    let(:inbox) { baileys_channel.inbox }

    context 'when channel_whatsapp_signature_enabled is on' do
      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'prepends the agent name in bold-italic' do
        expect(built_message.content).to eq("**_Agente Ficticio_**:\nOlá, como posso ajudar?")
      end
    end

    context 'when channel_whatsapp_signature_enabled is off' do
      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => false }) }

      it 'does not prepend the agent name' do
        expect(built_message.content).to eq('Olá, como posso ajudar?')
      end
    end

    context 'when only the API toggle is on' do
      before { user.update!(ui_settings: { 'channel_api_signature_enabled' => true }) }

      it 'does not prepend the agent name on Baileys' do
        expect(built_message.content).to eq('Olá, como posso ajudar?')
      end
    end

    context 'when provider is Meta Cloud' do
      let(:cloud_channel) do
        create(
          :channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                             validate_provider_config: false, received_messages: false, sync_templates: false
        )
      end
      let(:inbox) { cloud_channel.inbox }

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'does not prepend the agent name' do
        expect(built_message.content).to eq('Olá, como posso ajudar?')
      end
    end

    context 'when the message is private' do
      let(:params) do
        ActionController::Parameters.new({ content: 'Nota interna', private: true })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'does not prepend the agent name' do
        expect(built_message.content).to eq('Nota interna')
      end
    end

    context 'when an inbound message is attempted via the builder' do
      let(:params) do
        ActionController::Parameters.new({ content: 'Resposta do contato', message_type: 'incoming' })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'is rejected by the builder before any name prefix could apply' do
        expect { built_message }.to raise_error(StandardError, 'Incoming messages are only allowed in Api inboxes')
      end
    end

    context 'when content is already prefixed with the new format' do
      let(:params) do
        ActionController::Parameters.new({ content: "**_Agente Ficticio_**:\nOlá, como posso ajudar?" })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'does not double-prefix' do
        expect(built_message.content).to eq("**_Agente Ficticio_**:\nOlá, como posso ajudar?")
      end
    end

    context 'when content carries the legacy prefix for the same sender' do
      let(:params) do
        ActionController::Parameters.new({ content: "*Agente Ficticio*:\nOlá, como posso ajudar?" })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'normalizes to bold-italic once, preserving the body bytes' do
        expect(built_message.content).to eq("**_Agente Ficticio_**:\nOlá, como posso ajudar?")
      end
    end

    context 'when the legacy prefix is standalone for the same sender' do
      let(:params) do
        ActionController::Parameters.new({ content: '*Agente Ficticio*:' })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'normalizes the standalone prefix without fabricating a body' do
        expect(built_message.content).to eq('**_Agente Ficticio_**:')
      end
    end

    context 'when content carries the interim single-star prefix for the same sender' do
      let(:params) do
        ActionController::Parameters.new({ content: "*_Agente Ficticio_*:\nOlá, como posso ajudar?" })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'upgrades to CommonMark bold-italic once, preserving the body bytes' do
        expect(built_message.content).to eq("**_Agente Ficticio_**:\nOlá, como posso ajudar?")
      end
    end

    context 'when the interim single-star prefix is standalone for the same sender' do
      let(:params) do
        ActionController::Parameters.new({ content: '*_Agente Ficticio_*:' })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'upgrades the standalone prefix without fabricating a body' do
        expect(built_message.content).to eq('**_Agente Ficticio_**:')
      end
    end

    context 'when the message carries a caption with an attachment' do
      let(:params) do
        ActionController::Parameters.new({
                                          content: 'foto da recepção',
                                          attachments: [Rack::Test::UploadedFile.new('spec/assets/avatar.png', 'image/png')]
                                        })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'signs the caption with the new prefix and keeps the attachment on the first message' do
        expect(built_message.content).to eq("**_Agente Ficticio_**:\nfoto da recepção")
        expect(built_message.attachments.size).to eq(1)
      end
    end

    context 'when the legacy prefix belongs to a different sender' do
      let(:params) do
        ActionController::Parameters.new({ content: "*Outro Ficticio*:\nOlá" })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'keeps the foreign prefix and prepends the current sender' do
        expect(built_message.content).to eq("**_Agente Ficticio_**:\n*Outro Ficticio*:\nOlá")
      end
    end

    context 'when content is empty' do
      let(:params) do
        ActionController::Parameters.new({ content: '' })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'does not create a standalone name message' do
        expect(built_message.content).to eq('')
      end
    end

    context 'when sender is AgentBot' do
      let(:agent_bot) { create(:agent_bot, account: account) }
      let(:params) do
        ActionController::Parameters.new({
                                           content: 'Olá',
                                           sender_type: 'AgentBot',
                                           sender_id: agent_bot.id
                                         })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'does not prepend the agent name' do
        expect(built_message.content).to eq('Olá')
      end
    end

    context 'when relay_origin is bot' do
      let(:params) do
        ActionController::Parameters.new({
                                           content: 'Olá',
                                           content_attributes: { relay_origin: 'bot' }
                                         })
      end

      before { user.update!(ui_settings: { 'channel_whatsapp_signature_enabled' => true }) }

      it 'does not prepend the agent name' do
        expect(built_message.content).to eq('Olá')
      end
    end

    context 'when the agent name needs sanitizing' do
      before do
        user.update!(name: '  Agente *_Ficticio_*  ', display_name: '  Agente *_Ficticio_*  ',
                     ui_settings: { 'channel_whatsapp_signature_enabled' => true })
      end

      it 'strips asterisks, underscores and surrounding whitespace before prefixing' do
        expect(built_message.content).to eq("**_Agente Ficticio_**:\nOlá, como posso ajudar?")
      end
    end

    context 'when the agent name carries markup reserved by WhatsApp' do
      before do
        user.update!(name: 'Agente <b>Ficticio</b> *Ficticio*', display_name: 'Agente <b>Ficticio</b> *Ficticio*',
                     ui_settings: { 'channel_whatsapp_signature_enabled' => true })
      end

      it 'keeps plain-text name bytes without interpreting markup' do
        expect(built_message.content).to eq("**_Agente <b>Ficticio</b> Ficticio_**:\nOlá, como posso ajudar?")
      end
    end
  end

  describe 'API inbox regression' do
    let(:channel_api) { create(:channel_api, account: account) }
    let(:inbox) { channel_api.inbox }

    context 'when channel_api_signature_enabled is on' do
      before { user.update!(ui_settings: { 'channel_api_signature_enabled' => true }) }

      it 'still prepends the agent name' do
        expect(built_message.content).to eq("*Agente Ficticio*:\nOlá, como posso ajudar?")
      end
    end

    context 'when channel_api_signature_enabled is off' do
      before { user.update!(ui_settings: { 'channel_api_signature_enabled' => false }) }

      it 'does not prepend the agent name' do
        expect(built_message.content).to eq('Olá, como posso ajudar?')
      end
    end
  end
end
