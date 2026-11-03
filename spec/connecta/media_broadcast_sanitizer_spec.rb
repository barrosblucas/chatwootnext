require 'rails_helper'

# Sanitizador de midia do broadcast realtime (inbox marcada): remove `data_url`/
# `thumb_url` de anexos preservando ids/tipo/metadados, com marcador explicito de
# resolucao por viewer via GET autenticado. Modulo puro (sem DB/boot): cobre aqui
# o comportamento; a prova de dois viewers sem token compartilhado vive na
# `attachment_download_scope_spec` (download exige token proprio por viewer).
RSpec.describe Connecta::Scope::MediaBroadcastSanitizer do
  def message_with(attachments, extra = {})
    { id: 9, conversation_id: 3, account_id: 1, content: 'oi', attachments: attachments }.merge(extra)
  end

  def file_attachment(overrides = {})
    {
      id: 42, message_id: 9, file_type: 'image', account_id: 1,
      data_url: '/rails/active_storage/blobs/redirect/abc', thumb_url: '/rails/active_storage/representations/xyz',
      extension: 'jpg', file_size: 12
    }.merge(overrides)
  end

  it 'remove data_url/thumb_url, preserva ids/tipo/metadados e marca resolucao' do
    sanitized = described_class.sanitize_message(message_with([file_attachment]))

    expect(sanitized[:attachments].first).not_to have_key(:data_url)
    expect(sanitized[:attachments].first).not_to have_key(:thumb_url)
    expect(sanitized[:attachments].first).to include(id: 42, file_type: 'image', extension: 'jpg', file_size: 12)
    expect(sanitized[:connecta_media_resolve]).to be(true)
    expect(sanitized[:attachments].first[:connecta_media_resolve]).to be(true)
  end

  it 'nao modifica o hash original' do
    original = message_with([file_attachment])
    described_class.sanitize_message(original)

    expect(original[:attachments].first).to have_key(:data_url)
    expect(original).not_to have_key(:connecta_media_resolve)
  end

  it 'devolve o mesmo objeto quando nao ha URL de arquivo (inbox comum sem custo)' do
    plain = message_with([{ id: 1, file_type: 'contact', meta: {} }])
    expect(described_class.sanitize_message(plain)).to be(plain)

    no_attachments = { id: 1, content: 'texto' }
    expect(described_class.sanitize_message(no_attachments)).to be(no_attachments)
  end

  it 'e idempotente e entende chaves string (pos-serializacao do job)' do
    once = described_class.sanitize_message(message_with([file_attachment]))
    stringified = JSON.parse(once.to_json)
    twice = described_class.sanitize_message(stringified)

    expect(described_class.sanitized?(stringified)).to be(true)
    expect(twice['attachments'].first).not_to have_key('data_url')
    expect(twice['connecta_media_resolve']).to be(true)
  end

  it 'sanitiza messages e last_non_activity_message do payload de conversa' do
    payload = { id: 5, inbox_id: 7, messages: [message_with([file_attachment])],
                last_non_activity_message: message_with([file_attachment]) }

    sanitized = described_class.sanitize_conversation(payload)

    expect(sanitized[:messages].first[:connecta_media_resolve]).to be(true)
    expect(sanitized[:messages].first[:attachments].first).not_to have_key(:data_url)
    expect(sanitized[:last_non_activity_message][:attachments].first).not_to have_key(:thumb_url)
    expect(payload[:messages].first).not_to have_key(:connecta_media_resolve)
  end

  it 'nao toca payload de conversa sem mensagens com URL' do
    payload = { id: 5, inbox_id: 7, messages: [{ id: 1, content: 'oi' }] }
    expect(described_class.sanitize_conversation(payload)).to be(payload)
  end

  describe '.discard_unless_safe (fail-closed dos rescues)' do
    it 'devolve nil quando ha URL de arquivo (marcado ou escopo desconhecido)' do
      expect(described_class.discard_unless_safe(message_with([file_attachment]))).to be_nil
    end

    it 'devolve o proprio payload quando nao ha URL (nada a vazar)' do
      safe = { id: 1, content: 'oi' }
      expect(described_class.discard_unless_safe(safe)).to be(safe)
    end

    it 'enxerga URL aninhada em messages de conversa' do
      payload = { id: 5, inbox_id: 7, messages: [message_with([file_attachment])] }
      expect(described_class.payload_may_carry_file_urls?(payload)).to be(true)
      expect(described_class.discard_unless_safe(payload)).to be_nil
    end
  end

  describe 'BroadcastJobGuard fail-closed (barreira final, cobre message.created e first_reply_created)' do
    let(:recorder) do
      Module.new do
        def broadcast_to_members(members, event_name, data)
          (@sent ||= []) << [members, event_name, data]
        end

        def sent
          @sent || []
        end
      end
    end
    let(:job) do
      mod = recorder
      Class.new do
        include mod
        include Connecta::Scope::BroadcastJobGuard
      end.new
    end
    let(:live_link) { double('conversations', find_by: double('conversation', inbox_id: 11)) }

    before do
      allow(Account).to receive(:find_by).and_return(double('account', conversations: live_link))
    end

    it 'descarta (nil) em erro de lookup para message.created, sem transmitir original' do
      allow(Connecta::Scope::Projection).to receive(:marked?).and_raise(IOError, 'db down (injetado)')

      out = job.send(:connecta_scope_sanitize_media, message_with([file_attachment]), event_name: 'message.created')

      expect(out).to be_nil
    end

    it 'descarta (nil) em erro de lookup para first_reply_created' do
      allow(Connecta::Scope::Projection).to receive(:marked?).and_raise(IOError, 'db down (injetado)')

      out = job.send(:connecta_scope_sanitize_media, message_with([file_attachment]), event_name: 'first_reply.created')

      expect(out).to be_nil
    end

    it 'descarta quando o vinculo vivo sumiu (lookup nil) e ha URL; intacto sem URL' do
      allow(Connecta::Scope::Projection).to receive(:marked?).and_return(true)
      allow(Account).to receive(:find_by).and_return(nil)

      expect(job.send(:connecta_scope_sanitize_media, message_with([file_attachment]), event_name: 'message.created')).to be_nil

      safe = { id: 9, conversation_id: 3, account_id: 1, attachments: [{ id: 1, file_type: 'contact' }] }
      expect(job.send(:connecta_scope_sanitize_media, safe, event_name: 'message.created')).to be(safe)
    end

    it 'nao transmite sentinel nil; transmite dado normal' do
      job.send(:broadcast_to_members, ['t'], 'message.created', nil)
      expect(job.sent).to be_empty

      job.send(:broadcast_to_members, ['t'], 'message.created', { a: 1 })
      expect(job.sent.length).to eq(1)
    end

    it 'inbox nao marcada mantem payload intacto em sucesso' do
      allow(Connecta::Scope::Projection).to receive(:marked?).and_return(false)

      plain = message_with([file_attachment])
      expect(job.send(:connecta_scope_sanitize_media, plain, event_name: 'message.updated')).to be(plain)
    end
  end
end
