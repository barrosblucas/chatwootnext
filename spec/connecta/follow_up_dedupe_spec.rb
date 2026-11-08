require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Anexos de acompanhamento usam o endpoint nativo de mensagens com um nonce em
# content_attributes. O hook do fork dedupe no caminho oficial, sem fila
# fictícia nem campo novo de banco.
RSpec.describe 'Connecta · dedupe de anexos de acompanhamento', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:messages_path) { "#{conversations_path}/#{conv_a.display_id}/messages" }

  # Grava o valor JSON bruto na coluna, inclusive formatos que o coder do model
  # normalizaria (scalar/array e o objeto serializado dentro de string).
  def raw_content_attribute(message, value)
    connection = Message.connection
    raw = value.nil? ? 'NULL' : connection.quote(value.to_json)
    connection.execute("UPDATE messages SET content_attributes = #{raw} WHERE id = #{message.id.to_i}")
  end

  def post_follow_up(nonce, content)
    post messages_path,
         params: {
           content: content,
           content_attributes: { connecta_followup_nonce: nonce }.to_json,
           private: false
         },
         headers: agent_a.create_new_auth_token
  end

  it 'retry do mesmo nonce devolve a mensagem existente' do
    expect { post_follow_up('follow-1', 'anexo 1') }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok).or have_http_status(:created)

    expect { post_follow_up('follow-1', 'anexo 1') }.not_to change(Message, :count)
    expect(response).to have_http_status(:ok)
  end

  it 'nonces distintos criam mensagens distintas' do
    expect do
      post_follow_up('follow-a', 'anexo a')
      post_follow_up('follow-b', 'anexo b')
    end.to change(Message, :count).by(2)
  end

  it 'ignora content_attributes escalar/null/array e deduplica objeto e serializado' do
    base_params = { account: account, inbox: whatsapp_inbox, conversation: conv_a,
                    sender: agent_a, message_type: :outgoing }
    [123, nil, [1, 2]].each do |value|
      raw_content_attribute(create(:message, **base_params, content: "formato #{value.inspect}"), value)
    end
    legacy = create(:message, **base_params, content: 'legado')
    raw_content_attribute(legacy, { connecta_followup_nonce: 'legacy-nonce' }.to_json)

    expect { post_follow_up('follow-object', 'novo objeto') }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok).or have_http_status(:created)
    expect { post_follow_up('follow-object', 'novo objeto') }.not_to change(Message, :count)

    expect { post_follow_up('legacy-nonce', 'legado retry') }.not_to change(Message, :count)
    expect(response).to have_http_status(:ok)
    expect(Message.find_by!(content: 'legado').id).to eq(legacy.id)
  end

  it 'decodifica objeto e serializado e ignora string/escalar/null/array malformados' do
    decoder = Object.new.extend(Connecta::Scope::FollowUpDedupeHook)

    expect(decoder.send(:follow_up_nonce, { connecta_followup_nonce: 'objeto' }.to_json)).to eq('objeto')
    expect(decoder.send(:follow_up_nonce, { connecta_followup_nonce: 'serializado' }.to_json.to_json))
      .to eq('serializado')
    ['texto connecta_followup_nonce sem json', '123', 'null', '[1,2]'].each do |raw|
      expect(decoder.send(:follow_up_nonce, raw)).to be_nil
    end
  end

  it 'retry de dois anexos após perda de resposta mantém uma mensagem por nonce' do
    headers = agent_a.create_new_auth_token
    send_file = lambda do |nonce|
      post messages_path,
           params: {
             content: '',
             content_attributes: { connecta_followup_nonce: nonce }.to_json,
             private: false,
             attachments: [Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')]
           },
           headers: headers
    end

    expect do
      send_file.call('follow-file-1')
      send_file.call('follow-file-2')
    end.to change(Message, :count).by(2)
    expect(response).to have_http_status(:ok).or have_http_status(:created)
    messages = Message.where(conversation_id: conv_a.id).order(:id).last(2)
    expect(messages.map { |message| message.attachments.count }).to eq([1, 1])

    expect do
      send_file.call('follow-file-1')
      send_file.call('follow-file-2')
    end.not_to change(Message, :count)
    expect(Message.where(conversation_id: conv_a.id).order(:id).last(2))
      .to match_array(messages)
    messages.each { |message| expect(message.reload.attachments.count).to eq(1) }
  end
end
