require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 parte B3 (socket, spike G0) e c2a: conversa de inbox marcada só chega a quem o Gate lê; admin recebe só metadados.
# Listener, Gate e fixture são os reais; só o job de broadcast é observado (ActiveJob de teste). Nada é mockado.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe ActionCableListener do # rubocop:disable RSpec/SpecFilePathFormat -- nome do arquivo fixado pelo T0.2 (scope_socket_spec.rb)
  include_context 'with connecta g0 scope fixture'

  let(:listener) { described_class.instance }
  let(:fixture_users) { [agent_a, agent_b, manager_a, member_without_grant, admin_nominal, native_admin] }
  let(:admin_tokens) { [admin_nominal.pubsub_token, native_admin.pubsub_token] }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let!(:message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a) }
  let!(:control_message) { create(:message, account: account, inbox: control_inbox, conversation: conv_control) }
  let!(:orphan_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_orphan) }

  # Dispara o evento e devolve o payload que cada usuário da fixture recebeu (job nativo ou de metadados de admin).
  # Tokens de contato ficam de fora.
  def payloads_by_token
    clear_enqueued_jobs
    yield
    fixture_tokens = fixture_users.map(&:pubsub_token)
    broadcast_jobs = [ActionCableBroadcastJob, Connecta::Scope::AdminMetadataBroadcastJob]
    enqueued_jobs.each_with_object({}) do |job, received|
      next unless broadcast_jobs.include?(job[:job])

      tokens, _event_name, payload = ActiveJob::Arguments.deserialize(job[:args])
      tokens.each { |token| received[token] = payload if fixture_tokens.include?(token) }
    end
  end

  # Todos os tokens que receberam broadcast no bloco, stream da conta incluído (contato sem vínculo vai para ele).
  def broadcast_tokens
    clear_enqueued_jobs
    yield
    enqueued_jobs.flat_map { |job| ActiveJob::Arguments.deserialize(job[:args]).first }
  end

  describe 'conversa de inbox marcada' do
    let(:message_created) { Events::Base.new(:'message.created', Time.zone.now, message: message) }

    it 'agente com grant recebe a mensagem' do
      expect(payloads_by_token { listener.message_created(message_created) }.keys).to include(agent_a.pubsub_token)
    end

    it 'gestor com acompanhar recebe a leitura' do
      expect(payloads_by_token { listener.message_created(message_created) }.keys).to include(manager_a.pubsub_token)
    end

    it 'agente de outro setor não recebe' do
      expect(payloads_by_token { listener.message_created(message_created) }.keys).not_to include(agent_b.pubsub_token)
    end

    it 'membro da inbox sem grant não recebe' do
      expect(payloads_by_token { listener.message_created(message_created) }.keys).not_to include(member_without_grant.pubsub_token)
    end

    it 'admin nominal recebe só id da mensagem e da conversa; nativo same-account recebe full com conteúdo' do
      received = payloads_by_token { listener.message_created(message_created) }

      expect(received[admin_nominal.pubsub_token]).to eq(id: message.id, conversation_id: conv_a.display_id, account_id: account.id)
      nominal_keys = received[admin_nominal.pubsub_token].keys
      expect(nominal_keys).not_to include(:content, :attachments, :sender, :conversation, :meta, :messages)
      expect(received[native_admin.pubsub_token]).to include(:content, :conversation)
    end

    it 'agente com grant recebe o payload completo, com conteúdo' do
      expect(payloads_by_token { listener.message_created(message_created) }[agent_a.pubsub_token]).to include(:content, :conversation)
    end

    it 'payload com conteúdo chega exatamente a quem o Gate lê (agente+gestor+nativo full, sem nominal)' do
      received = payloads_by_token { listener.message_created(message_created) }
      content_keys = received.select { |_token, payload| payload.key?(:content) }.keys

      expect(content_keys).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    end

    it 'conversa sem escopo registrado: só nominal recebe metadados; nativo same-account recebe full' do
      orphan_created = Events::Base.new(:'message.created', Time.zone.now, message: orphan_message)

      expect(payloads_by_token { listener.message_created(orphan_created) }.keys)
        .to contain_exactly(admin_nominal.pubsub_token, native_admin.pubsub_token)
      expect(payloads_by_token { listener.message_created(orphan_created) }[native_admin.pubsub_token]).to include(:content)
      expect(payloads_by_token { listener.message_created(orphan_created) }[admin_nominal.pubsub_token]).to eq(
        id: orphan_message.id, conversation_id: conv_orphan.display_id, account_id: account.id
      )
    end

    it 'message.updated segue o mesmo filtro: nominal só metadados, nativo full com conteúdo' do
      event = Events::Base.new(:'message.updated', Time.zone.now, message: message, previous_changes: { content: %w[antes depois] })
      received = payloads_by_token { listener.message_updated(event) }

      expect(received.keys).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token, admin_nominal.pubsub_token)
      expect(received[admin_nominal.pubsub_token]).to eq(id: message.id, conversation_id: conv_a.display_id, account_id: account.id)
      expect(received[native_admin.pubsub_token]).to include(:content)
    end

    it 'conversation.updated segue o mesmo filtro; nominal só metadados, nativo full com conteúdo + setor' do
      event = Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conv_a)
      received = payloads_by_token { listener.conversation_updated(event) }

      expect(received.keys).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token, admin_nominal.pubsub_token)
      expect(received[admin_nominal.pubsub_token]).to eq(
        id: conv_a.display_id, inbox_id: whatsapp_inbox.id, status: conv_a.status, org_unit_id: org_a.id, account_id: account.id
      )
      expect(received[native_admin.pubsub_token]).to include(:id)
    end

    it 'assignee.changed entrega a nominal só metadados e a nativo conteúdo completo' do
      event = Events::Base.new(:'assignee.changed', Time.zone.now, conversation: conv_a)
      received = payloads_by_token { listener.assignee_changed(event) }

      expect(received[admin_nominal.pubsub_token]).to eq(
        id: conv_a.display_id, inbox_id: whatsapp_inbox.id, status: conv_a.status, org_unit_id: org_a.id, account_id: account.id
      )
      expect(received[native_admin.pubsub_token]).to include(:id)
    end
  end

  describe 'revogação' do
    let(:message_created) { Events::Base.new(:'message.created', Time.zone.now, message: message) }

    it 'grant removido deixa de receber no próximo evento' do
      expect(payloads_by_token { listener.message_created(message_created) }.keys).to include(agent_a.pubsub_token)

      Connecta::Scope::UserGrant.find_by!(user_id: agent_a.id).destroy!

      expect(payloads_by_token { listener.message_created(message_created) }.keys).not_to include(agent_a.pubsub_token)
    end

    it 'sessão revogada localmente deixa de receber no próximo evento' do
      expect(payloads_by_token { listener.message_created(message_created) }.keys).to include(agent_a.pubsub_token)

      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(revoked_locally_at: Time.current)

      expect(payloads_by_token { listener.message_created(message_created) }.keys).not_to include(agent_a.pubsub_token)
    end
  end

  describe 'conversation.mentioned' do
    it 'agente com grant no setor é avisado da menção' do
      event = Events::Base.new(:'conversation.mentioned', Time.zone.now, conversation: conv_a, user: agent_a)

      expect(payloads_by_token { listener.conversation_mentioned(event) }.keys).to contain_exactly(agent_a.pubsub_token)
    end

    it 'agente de outro setor mencionado não é avisado' do
      event = Events::Base.new(:'conversation.mentioned', Time.zone.now, conversation: conv_a, user: agent_b)

      expect(payloads_by_token { listener.conversation_mentioned(event) }).to be_empty
    end

    it 'membro sem grant mencionado não é avisado' do
      event = Events::Base.new(:'conversation.mentioned', Time.zone.now, conversation: conv_a, user: member_without_grant)

      expect(payloads_by_token { listener.conversation_mentioned(event) }).to be_empty
    end

    it 'admin nominal mencionado não recebe a menção (nominal segue fora do socket)' do
      event = Events::Base.new(:'conversation.mentioned', Time.zone.now, conversation: conv_a, user: admin_nominal)

      expect(payloads_by_token { listener.conversation_mentioned(event) }).to be_empty
    end

    it 'controle: menção em conversa de inbox não marcada segue a nativa' do
      event = Events::Base.new(:'conversation.mentioned', Time.zone.now, conversation: conv_control, user: member_without_grant)

      expect(payloads_by_token { listener.conversation_mentioned(event) }.keys).to contain_exactly(member_without_grant.pubsub_token)
    end
  end

  describe 'conversation.unread_count_changed' do
    before { account.enable_features!('conversation_unread_counts') }

    it 'só agente com grant, gestor e nativo full recebem a contagem de conversa marcada' do
      event = Events::Base.new(:'conversation.unread_count_changed', Time.zone.now, conversation: conv_a)

      expect(payloads_by_token { listener.conversation_unread_count_changed(event) }.keys)
        .to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    end

    it 'controle: inbox não marcada mantém membros e admin nativo' do
      event = Events::Base.new(:'conversation.unread_count_changed', Time.zone.now, conversation: conv_control)

      expect(payloads_by_token { listener.conversation_unread_count_changed(event) }.keys)
        .to contain_exactly(agent_a.pubsub_token, native_admin.pubsub_token)
    end
  end

  describe 'controle: conversa de inbox não marcada' do
    it 'mantém os destinatários nativos (membros e admins)' do
      control_created = Events::Base.new(:'message.created', Time.zone.now, message: control_message)

      expect(payloads_by_token { listener.message_created(control_created) }.keys).to contain_exactly(agent_a.pubsub_token, native_admin.pubsub_token)
    end
  end

  describe 'digitação e gravação de conversa marcada' do
    it 'digitação do cliente chega a agente com grant, gestor e nativo full (sem nominal)' do
      event = Events::Base.new(:'conversation.typing_on', Time.zone.now, conversation: conv_a, user: contact_a)

      expect(payloads_by_token { listener.conversation_typing_on(event) }.keys)
        .to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    end

    it 'fim de digitação segue o mesmo filtro' do
      event = Events::Base.new(:'conversation.typing_off', Time.zone.now, conversation: conv_a, user: contact_a)

      expect(payloads_by_token { listener.conversation_typing_off(event) }.keys)
        .to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    end

    it 'gravação de áudio segue o mesmo filtro' do
      event = Events::Base.new(:'conversation.recording', Time.zone.now, conversation: conv_a, user: contact_a)

      expect(payloads_by_token { listener.conversation_recording(event) }.keys)
        .to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    end

    it 'controle: digitação em inbox não marcada mantém membros e admin nativo' do
      event = Events::Base.new(:'conversation.typing_on', Time.zone.now, conversation: conv_control, user: contact_control)

      expect(payloads_by_token { listener.conversation_typing_on(event) }.keys).to contain_exactly(agent_a.pubsub_token, native_admin.pubsub_token)
    end
  end

  describe 'contato vinculado a inbox marcada' do
    it 'atualização vai só a quem o ContactVisibility permite ver, sem stream da conta' do
      event = Events::Base.new(:'contact.updated', Time.zone.now, contact: contact_a)

      expect(broadcast_tokens { listener.contact_updated(event) }).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token)
    end

    it 'criação segue a mesma regra' do
      event = Events::Base.new(:'contact.created', Time.zone.now, contact: contact_a)

      expect(broadcast_tokens { listener.contact_created(event) }).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token)
    end

    it 'fusão segue a mesma regra' do
      event = Events::Base.new(:'contact.merged', Time.zone.now, contact: contact_a)

      expect(broadcast_tokens { listener.contact_merged(event) }).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token)
    end

    it 'agrupamento de grupo segue a mesma regra' do
      event = Events::Base.new(:'contact.group_synced', Time.zone.now, contact: contact_a)

      expect(broadcast_tokens { listener.contact_group_synced(event) }).to contain_exactly(agent_a.pubsub_token, manager_a.pubsub_token)
    end

    it 'controle: contato sem vínculo com inbox marcada segue no stream da conta' do
      event = Events::Base.new(:'contact.updated', Time.zone.now, contact: contact_control)

      expect(broadcast_tokens { listener.contact_updated(event) }).to contain_exactly("account_#{account.id}")
    end
  end
end
