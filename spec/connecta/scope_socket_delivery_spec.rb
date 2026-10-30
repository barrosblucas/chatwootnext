require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF5 socket pendente (spike G0, rev. 2, bloco F1): ActionCableBroadcastJob REAL
# serializado apos enqueue autorizado pelo LISTENER NATIVO, com revogacao/
# transferencia/epoch/avanco-de-papel revalidados na execucao. Casos ESCRITOS e
# NAO EXECUTADOS; C1..C3 implementam DeliveryCheck/guard/socket_hook em runtime
# (plano rev. 2, l. 195-230). Somente API publica nativa: listener REAL
# (ActionCableListener.instance), enqueued_jobs, round-trip JSON,
# ActiveJob::Base.execute, ORM fixtures e boundary stubado
# ActionCable.server.broadcast (sem rede). Nenhum DeliveryCheck/
# DeliveryBinding/guard/job fake construido p/ marcar job como correto; os
# guards futuros capturam na Execucao (bloco D). Args reais do Job/Listener
# lidos: action_cable_listener.rb:363 (perform_later tokens, event, payload),
# action_cable_broadcast_job.rb:25,39 (rele + fan-out). Sem ContactDeleted/
# AdminMetadata (F2/F3 separados), sem 41B3/Native email, sem app/installer/
# helpers/shared/support/planos, sem runtime verde.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Casos F1 juntam destinatarios+conteudo por caso (AC1/AC2); comparacao direta
# de recipients (tokens), nunca assert global de ausencia (manager/cidadao
# continuam autorizados); sem novos destinatarios quando grants surgem.
# Maximo 5 expects por exemplo (< Max 7 do repo); sem disable, como a frente
# 41 (scope_notification_delivery_spec.rb, 0 ofensas sem disable).
RSpec.describe 'Connecta G0 · socket pendente apos perda de acesso (RF5/F1)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:listener) { ActionCableListener.instance }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let!(:marked_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a) }
  let!(:control_message) { create(:message, account: account, inbox: control_inbox, conversation: conv_control) }

  # Job REAL enfileirado pelo LISTENER NATIVO: toma o ultimo
  # ActionCableBroadcastJob de enqueued_jobs, faz o round-trip JSON do plano
  # (l. 280-282) e devolve o payload pronto p/ ActiveJob::Base.execute.
  def serialized_broadcast_hash
    job_entry = enqueued_jobs.reverse.find { |entry| entry[:job] == ActionCableBroadcastJob }
    expect(job_entry).not_to be_nil
    JSON.parse(job_entry.except(:job, :args, :queue, :priority, :at).to_json)
  end

  # Recipients do job serializado: desserializa args NATIVOS (tokens, event, payload)
  # via ActiveJob::Arguments.deserialize (mesmo padrao do scope_socket_spec.rb:33).
  def enqueued_broadcast_args
    job_entry = enqueued_jobs.reverse.find { |entry| entry[:job] == ActionCableBroadcastJob }
    expect(job_entry).not_to be_nil
    ActiveJob::Arguments.deserialize(job_entry[:args])
  end

  # executes the serialized job capturing the REAL network boundary (ActionCable.server.broadcast): returns [[stream, event, data], ...].
  def execute_and_collect(payload_hash)
    collected = []
    allow(ActionCable.server).to receive(:broadcast) do |stream, message|
      collected << [stream, message[:event], message[:data]]
    end
    ActiveJob::Base.execute(payload_hash)
    collected
  end

  # Audit sample.
  # Broadcast streams. Full-body tokens.
  def broadcast_streams(collected)
    collected.map(&:first)
  end

  def full_body_tokens(collected)
    collected.select { |_stream, _event, data| data.key?(:content) || data.key?('content') }.map(&:first)
  end

  before do
    clear_enqueued_jobs
  end

  after do
    clear_enqueued_jobs
  end

  it 'positivo autorizado: message.created chega a A e manager_a com full body; nominal só metadados e nativo full com conteúdo' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    tokens, event_name, _payload = enqueued_broadcast_args
    expect(event_name).to eq('message.created')
    payload_hash = serialized_broadcast_hash

    expect(tokens).to include(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)

    expect(streams).to include(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    bodies = full_body_tokens(collected)
    expect(bodies).to include(agent_a.pubsub_token, manager_a.pubsub_token, native_admin.pubsub_token)
    expect(bodies).not_to include(admin_nominal.pubsub_token)
  end

  it 'native admin full same-account: conteúdo completo realtime com auditoria, sem metadata duplicada' do
    before_count = Connecta::Scope::AccessAudit.where(user_id: native_admin.id, surface: 'conversation').count
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    tokens, = enqueued_broadcast_args
    payload_hash = serialized_broadcast_hash
    broadcasts = enqueued_jobs.select { |job| job[:job] == Connecta::Scope::AdminMetadataBroadcastJob }
    admin_tokens = broadcasts.flat_map { |job| ActiveJob::Arguments.deserialize(job[:args]).first }

    expect(tokens).to include(native_admin.pubsub_token)
    expect(admin_tokens).not_to include(native_admin.pubsub_token)
    collected = execute_and_collect(payload_hash)
    data_by_stream = collected.to_h { |stream, _event, data| [stream, data] }
    body = data_by_stream[native_admin.pubsub_token] || {}

    expect(data_by_stream.keys).to include(native_admin.pubsub_token)
    expect(body[:content] || body['content']).to eq(marked_message.content)
    audit = Connecta::Scope::AccessAudit.where(user_id: native_admin.id, surface: 'conversation').order(:id).last

    expect(audit&.decision).to eq('allow')
    expect(audit&.conversation_id).to eq(conv_a.id)
    expect(audit&.id).to be > before_count
  end

  it 'dual role: native admin atual com grant nominal verificado recebe conteúdo pleno same-account, sem metadados' do
    Connecta::Scope::UserAuthEpoch.create!(user_id: native_admin.id, epoch: 1)
    Connecta::Scope::UserGrant.create!(user_id: native_admin.id, org_unit: org_root, permission: 'admin_nominal')
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    tokens, = enqueued_broadcast_args
    payload_hash = serialized_broadcast_hash
    broadcasts = enqueued_jobs.select { |job| job[:job] == Connecta::Scope::AdminMetadataBroadcastJob }
    admin_tokens = broadcasts.flat_map { |job| ActiveJob::Arguments.deserialize(job[:args]).first }

    expect(tokens).to include(native_admin.pubsub_token)
    expect(admin_tokens).not_to include(native_admin.pubsub_token)
    collected = execute_and_collect(payload_hash)
    data_by_stream = collected.to_h { |stream, _event, data| [stream, data] }
    body = data_by_stream[native_admin.pubsub_token] || {}
    expect(data_by_stream.keys).to include(native_admin.pubsub_token)
    expect(body[:content] || body['content']).to eq(marked_message.content)
    expect(body[:sender] || body['sender']).not_to be_nil
  end

  it 'dual role: Gate audita allow no realtime same-account (precedência nativa, sem bypass)' do
    Connecta::Scope::UserAuthEpoch.create!(user_id: native_admin.id, epoch: 1)
    Connecta::Scope::UserGrant.create!(user_id: native_admin.id, org_unit: org_root, permission: 'admin_nominal')
    before_count = Connecta::Scope::AccessAudit.where(user_id: native_admin.id, surface: 'conversation').count
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    audit = Connecta::Scope::AccessAudit.where(user_id: native_admin.id, surface: 'conversation').order(:id).last

    expect(audit&.decision).to eq('allow')
    expect(audit&.conversation_id).to eq(conv_a.id)
    expect(audit&.id).to be > before_count
  end

  it 'nominal wp mantém só metadados e sem conteúdo no canal normal (regressão nominal)' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    tokens, = enqueued_broadcast_args
    payload_hash = serialized_broadcast_hash
    metadata_jobs = enqueued_jobs.select { |job| job[:job] == Connecta::Scope::AdminMetadataBroadcastJob }
    metadata_tokens = metadata_jobs.flat_map { |job| ActiveJob::Arguments.deserialize(job[:args]).first }

    expect(tokens).not_to include(admin_nominal.pubsub_token)
    expect(metadata_tokens).to include(admin_nominal.pubsub_token)
    collected = execute_and_collect(payload_hash)
    bodies = full_body_tokens(collected)

    expect(broadcast_streams(collected)).not_to include(admin_nominal.pubsub_token)
    expect(bodies).not_to include(admin_nominal.pubsub_token)
  end

  it 'cross-account: admin da conta A não recebe conteúdo da conta B (multi-membership nega)' do
    other_account = create(:account)
    other_inbox = create(:inbox, account: other_account)
    other_contact = create(:contact, account: other_account)
    other_conversation = create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact)
    other_scope = Connecta::Scope::ConversationScope.create!(
      conversation_id: other_conversation.id, inbox_id: other_inbox.id, contact_id: other_contact.id,
      org_unit: org_a, state: 'active', case_protocol: 'CASO-X', case_version: 1
    )
    Connecta::Scope::ScopedInbox.create!(inbox_id: other_inbox.id, enforcement: 'enforce', maintenance: false)
    other_message = create(:message, account: other_account, inbox: other_inbox, conversation: other_conversation)

    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: other_message))
    tokens, = enqueued_broadcast_args
    payload_hash = serialized_broadcast_hash
    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)

    expect(tokens).not_to include(native_admin.pubsub_token)
    expect(streams).not_to include(native_admin.pubsub_token)
    expect(other_scope).to be_present
  end

  it 'rebaixamento/remove vínculo após enqueue não entrega conteúdo residual (revalidação background)' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash

    native_admin.account_users.find_by(account_id: account.id).update!(role: :agent)

    collected = execute_and_collect(payload_hash)

    expect(broadcast_streams(collected)).not_to include(native_admin.pubsub_token)
  end

  it 'dual role rebaixado/remove vínculo após enqueue não recebe conteúdo pleno (nominal válido segue metadata)' do
    Connecta::Scope::UserAuthEpoch.create!(user_id: native_admin.id, epoch: 1)
    Connecta::Scope::UserGrant.create!(user_id: native_admin.id, org_unit: org_root, permission: 'admin_nominal')
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash

    native_admin.account_users.find_by(account_id: account.id).update!(role: :agent)

    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)
    bodies = full_body_tokens(collected)

    expect(streams).not_to include(native_admin.pubsub_token)
    expect(bodies).not_to include(native_admin.pubsub_token)
    expect(streams).to include(manager_a.pubsub_token)
  end

  it 'dual role com epoch revogado nega conteúdo pleno; conta B nunca recebe da conta A' do
    Connecta::Scope::UserAuthEpoch.create!(user_id: native_admin.id, epoch: 1)
    Connecta::Scope::UserGrant.create!(user_id: native_admin.id, org_unit: org_root, permission: 'admin_nominal')
    other_account = create(:account)
    other_inbox = create(:inbox, account: other_account)
    other_contact = create(:contact, account: other_account)
    other_conversation = create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact)
    Connecta::Scope::ScopedInbox.create!(inbox_id: other_inbox.id, enforcement: 'enforce', maintenance: false)
    other_message = create(:message, account: other_account, inbox: other_inbox, conversation: other_conversation)
    Connecta::Scope::UserAuthEpoch.find_by!(user_id: native_admin.id).update!(revoked_locally_at: Time.current)

    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash
    collected = execute_and_collect(payload_hash)

    expect(broadcast_streams(collected)).not_to include(native_admin.pubsub_token)
    expect(other_message).to be_present
    expect(other_conversation.account_id).not_to eq(account.id)
  end

  it 'jobs atrasados/refiltro: contexto inválido ou conta conflitante nega sem vazar' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    stale_hash = serialized_broadcast_hash
    stale_hash['connecta_scope']['v'] = 999

    expect(execute_and_collect(stale_hash)).to be_empty

    conflict_hash = serialized_broadcast_hash
    conflict_hash['connecta_scope']['account_id'] = account.id + 999_999

    expect(execute_and_collect(conflict_hash)).to be_empty
  end

  it 'revoga grant de A após enqueue: sem broadcast para token antigo de A (manager e nativo preservados)' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    tokens, = enqueued_broadcast_args
    expect(tokens).to include(agent_a.pubsub_token)
    payload_hash = serialized_broadcast_hash
    expect(payload_hash.dig('connecta_scope', 'native_admins')).not_to be_nil

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all
    manager_still_granted = Connecta::Scope::UserGrant.exists?(user_id: manager_a.id)
    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)

    expect(manager_still_granted).to be(true)
    expect(streams).not_to include(agent_a.pubsub_token)
    expect(streams).to include(manager_a.pubsub_token, native_admin.pubsub_token)
    expect(broadcast_streams(collected)).not_to include('migrated-replacement-token')
  end

  it 'conversation.updated recarrega mensagem nova sem vazar a antiga ao leitor revogado' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash
    listener.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conv_a))
    updated_hash = serialized_broadcast_hash

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, content: 'nova apos enqueue')
    collected = execute_and_collect(updated_hash)
    streams = broadcast_streams(collected)

    expect(streams).not_to include(agent_a.pubsub_token)
    expect(streams).to include(manager_a.pubsub_token, native_admin.pubsub_token)
    old_bodies = collected.select { |stream, _event, _data| stream == agent_a.pubsub_token }
    expect(old_bodies).to be_empty
    expect(payload_hash['job_class']).to eq('ActionCableBroadcastJob')
  end

  it 'epoch mudou MAS grant permanece: serializado com epoch antiga nega A (binding por epoch, nao so por grant)' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash
    grants_kept = Connecta::Scope::UserGrant.where(user_id: agent_a.id).count
    Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(epoch: 2)

    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)

    expect(grants_kept).to be > 0
    expect(Connecta::Scope::UserGrant.where(user_id: agent_a.id).count).to be > 0
    expect(streams).not_to include(agent_a.pubsub_token)
  end

  it 'conversation.mentioned com sessao revogada localmente: A mencionada nao recebe nada' do
    event = Events::Base.new(:'conversation.mentioned', Time.zone.now, conversation: conv_a, user: agent_a)
    listener.conversation_mentioned(event)
    payload_hash = serialized_broadcast_hash

    Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(revoked_locally_at: Time.current)
    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)

    expect(streams).not_to include(agent_a.pubsub_token)
  end

  it 'notification.created autorizada e depois revogada: revogado nao recebe; controle conv_control segue nativo' do
    notification = create(:notification, user: agent_a, account: account, primary_actor: conv_a,
                                         notification_type: :conversation_assignment)
    clear_enqueued_jobs

    listener.notification_created(Events::Base.new(:'notification.created', Time.zone.now, notification: notification))
    payload_hash = serialized_broadcast_hash
    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all
    collected = execute_and_collect(payload_hash)

    expect(Notification.exists?(id: notification.id)).to be(true)
    expect(broadcast_streams(collected)).not_to include(agent_a.pubsub_token)

    control_notification = create(:notification, user: member_without_grant, account: account,
                                                 primary_actor: conv_control,
                                                 notification_type: :conversation_assignment)
    clear_enqueued_jobs
    listener.notification_created(Events::Base.new(:'notification.created', Time.zone.now, notification: control_notification))
    control_hash = serialized_broadcast_hash
    control_collected = execute_and_collect(control_hash)

    expect(broadcast_streams(control_collected)).to include(member_without_grant.pubsub_token)
  end

  it 'ordinario promovido a admin após enqueue não recebe full body (nominal segue sem conteúdo; nativo da conta recebe)' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash

    agent_a_account_user = agent_a.account_users.find_by(account_id: account.id)
    agent_a_account_user.update!(role: :administrator)
    admin_nominal_account_user = admin_nominal.account_users.find_by(account_id: account.id)
    admin_nominal_account_user.update!(role: :agent)
    collected = execute_and_collect(payload_hash)
    bodies = full_body_tokens(collected)

    expect(bodies).not_to include(agent_a.pubsub_token)
    expect(bodies).not_to include(admin_nominal.pubsub_token)
    expect(bodies).to include(native_admin.pubsub_token)
  end

  it 'retry serializa apos desserializacao sem recapturar epoch: mantem epoch 1 e nega apos epoch 2' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash

    job = ActiveJob::Base.deserialize(payload_hash)
    Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(epoch: 2)
    expect(job.serialize['connecta_scope']['users'].to_h[agent_a.id]).to eq(1)
    clear_enqueued_jobs
    job.enqueue
    retried_entry = enqueued_jobs.reverse.find { |entry| entry[:job] == ActionCableBroadcastJob }
    retried_hash = JSON.parse(retried_entry.except(:job, :args, :queue, :priority, :at).to_json)

    expect(retried_hash['connecta_scope']['users'].to_h[agent_a.id]).to eq(1)
    collected = execute_and_collect(retried_hash)

    expect(broadcast_streams(collected)).not_to include(agent_a.pubsub_token)
  end

  it 'tokens publicos do widget contato preservados e privateNotes nao vao p/ contato (comparacao direta)' do
    contact_inbox_token = conv_a.contact_inbox.pubsub_token
    widget_message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                                      message_type: :incoming, private: false, content: 'publico do widget')
    private_message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a,
                                       message_type: :outgoing, private: true, content: 'nota privada interna')

    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: widget_message))
    tokens, = enqueued_broadcast_args
    widget_hash = serialized_broadcast_hash
    widget_collected = execute_and_collect(widget_hash)

    expect(tokens).to include(contact_inbox_token)
    expect(broadcast_streams(widget_collected)).to include(contact_inbox_token)
    expect(broadcast_streams(widget_collected)).to include(agent_a.pubsub_token)

    clear_enqueued_jobs
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: private_message))
    private_tokens, = enqueued_broadcast_args
    private_hash = serialized_broadcast_hash
    private_collected = execute_and_collect(private_hash)

    expect(private_tokens).not_to include(contact_inbox_token)
    expect(broadcast_streams(private_collected)).not_to include(contact_inbox_token)
  end

  it 'metadata ausente (legado) ou ctx novo com versao invalida: fail closed em marcada; legado nativo/unmarked preservado' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    legacy_hash = serialized_broadcast_hash
    legacy_hash.delete('connecta_scope')
    legacy_collected = execute_and_collect(legacy_hash)

    expect(broadcast_streams(legacy_collected)).not_to include(agent_a.pubsub_token)

    invalid_hash = serialized_broadcast_hash
    invalid_hash['connecta_scope'] = { 'v' => 999, 'kind' => 'conversation' }
    invalid_collected = execute_and_collect(invalid_hash)

    expect(broadcast_streams(invalid_collected)).not_to include(agent_a.pubsub_token)

    clear_enqueued_jobs
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: control_message))
    control_hash = serialized_broadcast_hash
    control_hash.delete('connecta_scope')
    control_collected = execute_and_collect(control_hash)

    expect(broadcast_streams(control_collected)).to include(agent_a.pubsub_token)
  end

  it 'novo grant surgindo apos enqueue nao adiciona destinatarios: so quem estava autorizado no enqueue' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    tokens_before, = enqueued_broadcast_args
    payload_hash = serialized_broadcast_hash

    expect(tokens_before).not_to include(member_without_grant.pubsub_token)
    Connecta::Scope::UserGrant.create!(user_id: member_without_grant.id, org_unit: org_a, permission: 'atender')
    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)

    expect(streams).not_to include(member_without_grant.pubsub_token)
    expect(streams).to include(agent_a.pubsub_token, manager_a.pubsub_token)
  end

  it 'cidadao continua autorizado: token do contato recebe publico mesmo apos revogacao do agente' do
    listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: marked_message))
    payload_hash = serialized_broadcast_hash
    contact_token = conv_a.contact_inbox.pubsub_token

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all
    collected = execute_and_collect(payload_hash)
    streams = broadcast_streams(collected)

    expect(streams).not_to include(agent_a.pubsub_token)
    expect(streams).to include(contact_token, manager_a.pubsub_token)
  end
end
