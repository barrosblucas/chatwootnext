require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF5 admin metadata pendente (spike G0, rev. 2, bloco F3): metadados administrativos revalidados após revogação.
# Casos ESCRITOS e NÃO EXECUTADOS; E1 implementa o guard em runtime (plano rev. 2, l.266-277, l.303-309).
# Fixture test-only e listener nativo que enfileira AdminMetadataBroadcastJob; JSON round-trip e ActiveJob::Base.execute reais.
# Sem ctx fake como substituto do enqueue real; sem app code; sem rede.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe Connecta::Scope::AdminMetadataBroadcastJob do # rubocop:disable RSpec/SpecFilePathFormat -- nome fixado pelo plano RF5/F3
  include_context 'with connecta g0 scope fixture'

  let(:listener) { ActionCableListener.instance }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let!(:scoped_message) { create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a) }

  def message_created_event
    Events::Base.new(:'message.created', Time.zone.now, message: scoped_message)
  end

  def enqueued_admin_job
    enqueued_jobs.find { |job| job[:job] == Connecta::Scope::AdminMetadataBroadcastJob }
  end

  def roundtrip(job_hash)
    JSON.parse(job_hash.except(:job, :args, :queue, :priority, :at).to_json)
  end

  def enqueue_and_roundtrip
    clear_enqueued_jobs
    listener.message_created(message_created_event)
    roundtrip(enqueued_admin_job)
  end

  def broadcasts_by_token(job_payload)
    received = {}
    allow(ActionCable.server).to receive(:broadcast) do |token, payload|
      received[token] = payload[:data] || payload['data']
    end
    ActiveJob::Base.execute(job_payload)
    received
  end

  def metadata_for(received, user)
    received[user.pubsub_token]&.with_indifferent_access
  end

  before do
    clear_enqueued_jobs
  end

  after do
    clear_enqueued_jobs
  end

  it 'positivo: nominal recebe só id/conversation_id/account_id, sem body ou snippet; nativo full NÃO entra neste canal' do
    job_payload = enqueue_and_roundtrip
    received = broadcasts_by_token(job_payload)

    expect(received.keys).to include(admin_nominal.pubsub_token)
    expect(received.keys).not_to include(native_admin.pubsub_token)
    nominal = metadata_for(received, admin_nominal)
    native = metadata_for(received, native_admin)

    expect(nominal.slice('id', 'conversation_id', 'account_id').to_h).to eq(
      'id' => scoped_message.id, 'conversation_id' => conv_a.display_id, 'account_id' => account.id
    )
    expect(native).to be_nil
    expect(nominal.keys.map(&:to_s).sort).to eq(%w[account_id conversation_id id])
    expect(nominal.keys.map(&:to_s)).not_to include('body', 'snippet', 'content')
  end

  it 'grant admin_nominal removido: nominal não recebe; nativo full também não recebe neste canal' do
    job_payload = enqueue_and_roundtrip

    Connecta::Scope::UserGrant.find_by!(user_id: admin_nominal.id).destroy!

    received = broadcasts_by_token(job_payload)

    expect(received.keys).not_to include(admin_nominal.pubsub_token)
    expect(received.keys).not_to include(native_admin.pubsub_token)
  end

  it 'epoch 1 para 2 com grant: nominal não recebe; nativo full também não recebe neste canal' do
    job_payload = enqueue_and_roundtrip

    Connecta::Scope::UserAuthEpoch.find_by!(user_id: admin_nominal.id).update!(epoch: 2)

    received = broadcasts_by_token(job_payload)

    expect(received.keys).not_to include(admin_nominal.pubsub_token)
    expect(received.keys).not_to include(native_admin.pubsub_token)
  end

  it 'sessão revogada localmente: nominal não recebe; nativo full também não recebe neste canal' do
    job_payload = enqueue_and_roundtrip

    Connecta::Scope::UserAuthEpoch.find_by!(user_id: admin_nominal.id).update!(revoked_locally_at: Time.current)

    received = broadcasts_by_token(job_payload)

    expect(received.keys).not_to include(admin_nominal.pubsub_token)
    expect(received.keys).not_to include(native_admin.pubsub_token)
  end

  it 'native demovido para agent não ganha metadata; nominal válido ainda recebe' do
    job_payload = enqueue_and_roundtrip

    AccountUser.find_by!(account_id: account.id, user_id: native_admin.id).update!(role: :agent)

    received = broadcasts_by_token(job_payload)

    expect(received.keys).not_to include(native_admin.pubsub_token)
    expect(received.keys).to include(admin_nominal.pubsub_token)
    expect(metadata_for(received, admin_nominal).slice('id', 'conversation_id', 'account_id').to_h).to eq(
      'id' => scoped_message.id, 'conversation_id' => conv_a.display_id, 'account_id' => account.id
    )
  end

  it 'usuário vira admin após o enqueue: novo destino não recebe; só nominal capturado' do
    job_payload = enqueue_and_roundtrip

    Connecta::Scope::UserGrant.create!(user_id: agent_a.id, org_unit: org_root, permission: 'admin_nominal')

    received = broadcasts_by_token(job_payload)

    expect(received.keys).not_to include(agent_a.pubsub_token)
    expect(received.keys).to include(admin_nominal.pubsub_token)
    expect(received.keys).not_to include(native_admin.pubsub_token)
  end

  it 'nominal promovido a nativo após enqueue: metadata obsoleta não retransmite neste canal' do
    job_payload = enqueue_and_roundtrip
    grant = Connecta::Scope::UserGrant.find_by!(user_id: admin_nominal.id)

    AccountUser.find_by!(account_id: account.id, user_id: admin_nominal.id).update!(role: :administrator)

    received = broadcasts_by_token(job_payload)

    expect(grant).to be_present
    expect(received.keys).not_to include(admin_nominal.pubsub_token)
    expect(received.keys).not_to include(native_admin.pubsub_token)
  end

  it 'payload legado sem binding: nada é entregue' do
    clear_enqueued_jobs
    listener.message_created(message_created_event)
    real_hash = enqueued_admin_job
    tokens, event_name, data = ActiveJob::Arguments.deserialize(real_hash[:args])
    legacy_serialized = ActiveJob::Core.instance_method(:serialize).bind_call(described_class.new(tokens, event_name, data))
    legacy_payload = JSON.parse(legacy_serialized.to_json)

    expect(legacy_payload).not_to have_key('connecta_scope')

    received = broadcasts_by_token(legacy_payload)

    expect(received).to be_empty
  end
end
