require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF5 contato excluído com entregas pendentes (spike G0, rev. 2, bloco F2):
# jobs nativos de contact.deleted/contact.updated/message.created serializados
# antes da perda de acesso, com revogação/epoch/perda de vínculo revalidados na
# execução. Casos ESCRITOS e NÃO EXECUTADOS; K1/K2/K3 implementam Gate por
# escopo, classificação pré-destroy e contexto de contato em runtime
# (plano rev. 2, l. 235-261 e l. 293-302). Somente API pública nativa: listener
# REAL (ActionCableListener.instance), destroy real, enqueued_jobs, round-trip
# JSON, ActiveJob::Base.execute, ORM fixtures e boundary stubada
# ActionCable.server.broadcast (sem rede). Legado real = serialização nativa
# sem binding via ActiveJob::Core.instance_method(:serialize).bind_call, nunca
# stub de guard; nenhum DeliveryContext/DeliveryBinding/guard/job fake
# construído para marcar o job como correto — o shape 'connecta_scope'
# esperado abaixo (kind native/contact_deleted/contact_ambiguous/contact)
# vem do plano §1.2 e só existe em runtime após K3. Args reais do
# Job/Listener lidos: action_cable_listener.rb:255-276 (contact.* →
# perform_later tokens, event, payload), action_cable_broadcast_job.rb:13-18,
# 39 (fan-out por membro). Sem app/installer/helpers/shared/support/planos
# além dos estáveis, sem runtime verde.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Casos F2 juntam classificação + destinatários por caso (AC1/AC2); comparação
# direta de recipients (tokens), nunca assert global de ausência onde outro
# leitor segue autorizado (manager preservado); sem novos destinatários quando
# grants surgem; nunca stream account_* para contato marcado. Máximo 5
# expects por exemplo (< Max 7 do repo).
RSpec.describe 'Connecta G0 · contato excluído com entregas pendentes (RF5/F2)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:listener) { ActionCableListener.instance }

  # Contato vinculado à inbox marcada e visível a agent_a (atender) e
  # manager_a (acompanhar). Mesmo padrão de scope_team_contact_spec.rb:241-247:
  # a factory de conversa cria o ContactInbox marcado; o escopo torna o
  # contato visível no setor A.
  def create_marked_linked_contact!(protocol: 'CASO-F2')
    linked = create(:contact, account: account)
    conv = create(:conversation, account: account, inbox: whatsapp_inbox, contact: linked)
    Connecta::Scope::ConversationScope.create!(conversation_id: conv.id, inbox_id: whatsapp_inbox.id,
                                               contact_id: linked.id, org_unit: org_a, state: 'active',
                                               case_protocol: protocol, case_version: 1)
    linked
  end

  # Carga real que o Contact#dispatch_destroy_event envia
  # (contact.rb:257-265: push_event_data + account_id).
  def deleted_contact_data(contact)
    contact.push_event_data.merge(account_id: account.id)
  end

  # Job REAL enfileirado pelo LISTENER NATIVO: toma o último
  # ActionCableBroadcastJob de enqueued_jobs, faz o round-trip JSON do plano
  # (l. 280-282) e devolve o payload pronto para ActiveJob::Base.execute.
  def serialized_broadcast_hash
    job_entry = enqueued_jobs.reverse.find { |entry| entry[:job] == ActionCableBroadcastJob }
    expect(job_entry).not_to be_nil
    JSON.parse(job_entry.except(:job, :args, :queue, :priority, :at).to_json)
  end

  # Recipients do job serializado: desserializa args NATIVOS (tokens, event,
  # payload) via ActiveJob::Arguments.deserialize (mesmo padrão do
  # scope_socket_spec.rb:33).
  def enqueued_broadcast_args
    job_entry = enqueued_jobs.reverse.find { |entry| entry[:job] == ActionCableBroadcastJob }
    expect(job_entry).not_to be_nil
    ActiveJob::Arguments.deserialize(job_entry[:args])
  end

  # Legado real sem binding: serialização nativa do job construído à mão,
  # sem passar pelo SocketHook/binding futuro, + JSON round-trip.
  def legacy_roundtrip(tokens, event_name, payload)
    legacy_serialized = ActiveJob::Core.instance_method(:serialize).bind_call(
      ActionCableBroadcastJob.new(tokens, event_name, payload)
    )
    JSON.parse(legacy_serialized.to_json)
  end

  # Executa o job serializado capturando a boundary REAL de rede
  # (ActionCable.server.broadcast): devolve [[stream, event, data], ...].
  def execute_and_collect(payload_hash)
    collected = []
    allow(ActionCable.server).to receive(:broadcast) do |stream, message|
      collected << [stream, message[:event], message[:data]]
    end
    ActiveJob::Base.execute(payload_hash)
    collected
  end

  def broadcast_streams(collected)
    collected.map(&:first)
  end

  before do
    clear_enqueued_jobs
    whatsapp_inbox.update!(enable_auto_assignment: false)
    control_inbox.update!(enable_auto_assignment: false)
  end

  after do
    clear_enqueued_jobs
  end

  it 'legado contact.deleted marcado serializado antes do destroy não entrega após perda do vínculo' do
    contact_data = deleted_contact_data(contact_a)
    payload_hash = legacy_roundtrip(["account_#{account.id}"], 'contact.deleted', contact_data)

    expect(payload_hash).not_to have_key('connecta_scope')

    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    contact_id = contact_a.id
    contact_a.destroy!
    ContactInbox.where(contact_id: contact_id).delete_all

    expect(Contact.exists?(contact_id)).to be(false)
    expect(ContactInbox.exists?(contact_id: contact_id)).to be(false)
    expect(execute_and_collect(payload_hash)).to be_empty
  end

  it 'legado contact.updated de controle em conta marcada é conservadoramente bloqueado' do
    payload = contact_control.push_event_data.merge(account_id: account.id)
    payload_hash = legacy_roundtrip(["account_#{account.id}"], 'contact.updated', payload)

    expect(payload_hash).not_to have_key('connecta_scope')
    expect(Contact.exists?(contact_control.id)).to be(true)
    expect(execute_and_collect(payload_hash)).to be_empty
  end

  it 'legado message.created de conv_control segue nativo' do
    control_message = create(:message, account: account, inbox: control_inbox, conversation: conv_control)
    payload = control_message.push_event_data.merge(account_id: account.id)
    payload_hash = legacy_roundtrip([agent_a.pubsub_token], 'message.created', payload)

    expect(payload_hash).not_to have_key('connecta_scope')

    collected = execute_and_collect(payload_hash)

    expect(broadcast_streams(collected)).to include(agent_a.pubsub_token)
  end

  it 'legado contact.deleted em outra conta sem inbox marcada segue nativo' do
    other_account = create(:account)
    other_inbox = create(:inbox, account: other_account)
    other_contact = create(:contact, account: other_account)
    create(:contact_inbox, contact: other_contact, inbox: other_inbox)
    payload = other_contact.push_event_data.merge(account_id: other_account.id)
    payload_hash = legacy_roundtrip(["account_#{other_account.id}"], 'contact.deleted', payload)

    expect(payload_hash).not_to have_key('connecta_scope')

    collected = execute_and_collect(payload_hash)

    expect(broadcast_streams(collected)).to include("account_#{other_account.id}")
  end

  it 'novo destroy de contato só em inbox não marcada usa binding native e recebe stream da conta' do
    unmarked = create(:contact, account: account)
    create(:contact_inbox, contact: unmarked, inbox: control_inbox)
    create(:conversation, account: account, inbox: control_inbox, contact: unmarked)
    contact_data = unmarked.push_event_data.merge(account_id: account.id)
    contact_id = unmarked.id
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    unmarked.destroy!
    ContactInbox.where(contact_id: contact_id).delete_all

    clear_enqueued_jobs
    listener.contact_deleted(Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data))
    tokens, event_name, _payload = enqueued_broadcast_args
    payload_hash = serialized_broadcast_hash

    expect(event_name).to eq('contact.deleted')
    expect(tokens).to include("account_#{account.id}")
    expect(payload_hash['connecta_scope']).to include('v' => 1, 'kind' => 'native', 'account_id' => account.id,
                                                      'contact_id' => contact_id)
    expect(broadcast_streams(execute_and_collect(payload_hash))).to include("account_#{account.id}")
  end

  it 'novo destroy marcado com vínculos removidos mantém leitores com grant e nunca usa stream da conta' do
    linked = create_marked_linked_contact!(protocol: 'CASO-F2-A')
    contact_data = deleted_contact_data(linked)
    contact_id = linked.id
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    linked.destroy!
    ContactInbox.where(contact_id: contact_id).delete_all

    expect(ContactInbox.exists?(contact_id: contact_id)).to be(false)

    clear_enqueued_jobs
    listener.contact_deleted(Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data))
    payload_hash = serialized_broadcast_hash

    expect(payload_hash['connecta_scope']).to include('v' => 1, 'kind' => 'contact_deleted',
                                                      'account_id' => account.id, 'contact_id' => contact_id)

    streams = broadcast_streams(execute_and_collect(payload_hash))

    expect(streams).to include(agent_a.pubsub_token, manager_a.pubsub_token)
    expect(streams).not_to include("account_#{account.id}")
    expect(streams).not_to include(agent_b.pubsub_token)
  end

  it 'novo destroy marcado após revogar A: só A não recebe, manager ainda pode receber, sem stream amplo' do
    linked = create_marked_linked_contact!(protocol: 'CASO-F2-B')
    contact_data = deleted_contact_data(linked)
    contact_id = linked.id
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    linked.destroy!
    ContactInbox.where(contact_id: contact_id).delete_all

    clear_enqueued_jobs
    listener.contact_deleted(Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data))
    payload_hash = serialized_broadcast_hash
    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

    expect(Connecta::Scope::UserGrant.exists?(user_id: manager_a.id)).to be(true)

    streams = broadcast_streams(execute_and_collect(payload_hash))

    expect(streams).not_to include(agent_a.pubsub_token)
    expect(streams).to include(manager_a.pubsub_token)
    expect(streams).not_to include("account_#{account.id}")
  end

  it 'novo destroy marcado com epoch stale não entrega ao token antigo' do
    linked = create_marked_linked_contact!(protocol: 'CASO-F2-C')
    contact_data = deleted_contact_data(linked)
    contact_id = linked.id
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    linked.destroy!
    ContactInbox.where(contact_id: contact_id).delete_all

    clear_enqueued_jobs
    listener.contact_deleted(Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data))
    payload_hash = serialized_broadcast_hash
    Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(epoch: 2)

    expect(Connecta::Scope::UserGrant.where(user_id: agent_a.id).count).to be > 0

    streams = broadcast_streams(execute_and_collect(payload_hash))

    expect(streams).not_to include(agent_a.pubsub_token)
    expect(streams).to include(manager_a.pubsub_token)
    expect(streams).not_to include("account_#{account.id}")
  end

  it 'listener direto sem destroy em conta marcada vira ambiguous e não entrega' do
    contact_data = deleted_contact_data(contact_a)

    clear_enqueued_jobs
    listener.contact_deleted(Events::Base.new(:'contact.deleted', Time.zone.now, contact_data: contact_data))
    payload_hash = serialized_broadcast_hash

    expect(payload_hash['connecta_scope']).to include('v' => 1, 'kind' => 'contact_ambiguous',
                                                      'account_id' => account.id)
    expect(execute_and_collect(payload_hash)).to be_empty
  end

  it 'contact.updated novo de contato marcado com perda de grant não entrega ao revogado' do
    clear_enqueued_jobs
    listener.contact_updated(Events::Base.new(:'contact.updated', Time.zone.now, contact: contact_a))
    payload_hash = serialized_broadcast_hash

    expect(payload_hash['connecta_scope']).to include('v' => 1, 'kind' => 'contact', 'account_id' => account.id)

    Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

    streams = broadcast_streams(execute_and_collect(payload_hash))

    expect(streams).not_to include(agent_a.pubsub_token)
    expect(streams).to include(manager_a.pubsub_token)
    expect(streams).not_to include("account_#{account.id}")
  end
end
