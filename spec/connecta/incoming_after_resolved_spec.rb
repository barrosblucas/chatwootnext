require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_product_tables'

Connecta::G0ScopeSchema.ensure!
Connecta::G0ProductTables.install!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

# Decisão 005 no caminho REAL de ingestão Baileys: uma conversa resolvida não
# pode receber o próximo inbound. Com lock_to_single_conversation=false, o
# fluxo nativo cria conversa nova na mesma inbox/contato; o novo escopo nasce
# `reception`. O retry tardio do inbound antigo é idempotente por source_id.
RSpec.describe 'Connecta · inbound após conversa resolvida (Baileys real)', type: :request do # rubocop:disable RSpec/DescribeClass
  let(:webhook_verify_token) { 'valid_token' }
  let!(:account) { create(:account) }
  let!(:channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys',
                              provider_config: { webhook_verify_token: webhook_verify_token },
                              validate_provider_config: false, received_messages: false)
  end
  let!(:inbox) { channel.inbox.tap { |record| record.update!(lock_to_single_conversation: false, enable_auto_assignment: false) } }
  let!(:reception_unit) { Connecta::Scope::OrgUnit.create!(name: 'Recepção', path: '/recepcao/') }

  before do
    stub_request(:get, /profile-picture-url/).to_return(status: 200, body: { data: { profilePictureUrl: nil } }.to_json)
    Connecta::Scope::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
    stub_const('ENV', ENV.to_h.merge(
      'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
      'CONNECTA_RECEPTION_ORG_UNIT_ID' => reception_unit.id.to_s
    ))
  end

  # O after_create do runtime chama este mesmo criador no boot real; nos specs
  # o instalador global é evitado para não afetar outros exemplos do processo.
  def ensure_reception_scope(conversation)
    return if Connecta::Scope::ConversationScope.exists?(conversation_id: conversation.id)

    Connecta::Runtime::ReceptionScopeCreator.call(conversation)
  end

  def deliver(source_id, text)
    params = {
      webhookVerifyToken: webhook_verify_token,
      event: 'messages.upsert',
      data: {
        type: 'notify',
        messages: [{
          key: {
            id: source_id, remoteJid: '5511912345678@lid', remoteJidAlt: '5511912345678@s.whatsapp.net',
            fromMe: false, addressingMode: 'lid'
          },
          pushName: 'Cidadão Sintético',
          messageTimestamp: Time.current.to_i,
          message: { conversation: text }
        }]
      }
    }
    Whatsapp::IncomingMessageBaileysService.new(inbox: inbox, params: params).perform
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
  it 'cria conversa nova e preserva a anterior resolvida; retry antigo não duplica' do
    deliver('old-1', 'primeira mensagem')
    old_conversation = Conversation.find_by!(inbox: inbox)
    ensure_reception_scope(old_conversation)
    old_scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: old_conversation.id)
    old_scope.update!(state: 'active', case_protocol: 'CASO-OLD', case_version: 1)

    deliver('old-2', 'segunda mensagem')
    old_conversation.reload
    old_message_ids = old_conversation.messages.order(:id).pluck(:id)
    expect(old_message_ids.size).to eq(2)

    old_conversation.update!(status: :resolved)
    # after_update_commit pode ser adiado pelo transactional fixture. O mesmo
    # método de produção é idempotente; a spec de resolução cobre o callback.
    Connecta::Scope::ConversationResolution.resolve_scope!(old_conversation.reload) unless old_scope.reload.state == 'closed'
    expect(old_conversation.reload.status).to eq('resolved')
    expect(old_scope.reload.state).to eq('closed')
    expect(old_scope.closed_at).not_to be_nil
    expect(old_scope.case_protocol).to eq('CASO-OLD')
    expect(old_conversation.messages.order(:id).pluck(:id)).to eq(old_message_ids)

    expect do
      deliver('new-1', 'nova mensagem')
    end.to change(Conversation, :count).by(1)

    new_conversation = Conversation.where(inbox: inbox).where.not(id: old_conversation.id).sole
    ensure_reception_scope(new_conversation)
    new_scope = Connecta::Scope::ConversationScope.find_by!(conversation_id: new_conversation.id)
    expect(new_conversation.inbox_id).to eq(old_conversation.inbox_id)
    expect(new_conversation.contact_id).to eq(old_conversation.contact_id)
    expect(new_conversation.contact_inbox.source_id).to eq(old_conversation.contact_inbox.source_id)
    expect(new_conversation.display_id).not_to eq(old_conversation.display_id)
    expect(new_scope.state).to eq('reception')
    expect(new_scope.case_protocol).to be_nil
    expect(new_scope.org_unit_id).to eq(reception_unit.id)
    expect(new_conversation.status).to eq('open')
    expect(new_conversation.messages.pluck(:content)).to contain_exactly('nova mensagem')
    expect(old_conversation.reload.messages.order(:id).pluck(:id)).to eq(old_message_ids)
    expect(old_conversation.status).to eq('resolved')

    expect do
      deliver('new-2', 'outra mensagem')
    end.not_to change(Conversation, :count)
    expect(new_conversation.reload.messages.order(:id).pluck(:content)).to contain_exactly('nova mensagem', 'outra mensagem')
    expect(old_conversation.reload.messages.order(:id).pluck(:id)).to eq(old_message_ids)

    expect do
      deliver('old-2', 'segunda mensagem')
    end.not_to change(Conversation, :count)
    expect(new_conversation.reload.messages.count).to eq(2)
    expect(old_conversation.reload.messages.order(:id).pluck(:id)).to eq(old_message_ids)
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

  it 'exige lock_to_single_conversation=false para o novo inbound não reutilizar a resolvida' do
    expect(inbox.reload.lock_to_single_conversation).to be(false)
  end
end
