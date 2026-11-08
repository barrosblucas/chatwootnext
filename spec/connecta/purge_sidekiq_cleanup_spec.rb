require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

# Política do dead set: filas técnicas preservadas, alvo removido só quando
# classe + digests + hash de contagens batem. Nenhum arg/PII é impresso.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Connecta::Purge::SidekiqCleanup do
  let(:run_id) { SecureRandom.hex(4) }
  let(:keys) do
    {
      schedule: "connecta-purge-test:#{run_id}:schedule",
      retry: "connecta-purge-test:#{run_id}:retry",
      dead: "connecta-purge-test:#{run_id}:dead"
    }
  end

  def with_redis(&block)
    Sidekiq.redis(&block)
  end

  def clear_keys
    with_redis { |conn| conn.del(*keys.values) }
  end

  def add(key, klass, marker)
    raw = JSON.generate({ 'class' => klass, 'args' => [{ 'synthetic' => marker }] })
    with_redis { |conn| conn.zadd(key, Time.now.to_f, raw) }
    raw
  end

  def plan
    described_class.plan(keys: keys)
  end

  def apply(plan_hash)
    described_class.apply(
      expected_hash: plan_hash,
      confirmation: "APPLY:#{plan_hash}",
      writers_stopped: true,
      keys: keys
    )
  end

  before { clear_keys }
  after { clear_keys }

  it 'remove só dead Webhooks::WhatsappEventsJob e preserva scheduled/retry e PurgeJob' do
    scheduled = add(keys[:schedule], 'ActiveStorage::PurgeJob', 'arg-scheduled')
    retry_job = add(keys[:retry], 'SomeTechnicalJob', 'arg-retry')
    target = add(keys[:dead], 'Webhooks::WhatsappEventsJob', 'arg-target')
    preserved = add(keys[:dead], 'ActiveStorage::PurgeJob', 'arg-preserved')
    inspected = plan

    expect(inspected[:classes][:dead]).to include(
      'Webhooks::WhatsappEventsJob' => 1, 'ActiveStorage::PurgeJob' => 1
    )
    result = apply(inspected[:inventory_hash])

    expect(result[:status]).to eq('committed')
    expect(result[:discarded_dead]).to eq(1)
    expect(result[:preserved_scheduled]).to eq('ActiveStorage::PurgeJob' => 1)
    expect(result[:preserved_retry]).to eq('SomeTechnicalJob' => 1)
    expect(result[:dead_after]).to eq('ActiveStorage::PurgeJob' => 1)
    expect(result.to_json).not_to include('arg-')

    expect(with_redis { |conn| conn.zrange(keys[:schedule], 0, -1) }).to eq([scheduled])
    expect(with_redis { |conn| conn.zrange(keys[:retry], 0, -1) }).to eq([retry_job])
    expect(with_redis { |conn| conn.zrange(keys[:dead], 0, -1) }).to eq([preserved])
    expect(target).to be_present
  end

  it 'aborta quando um dead alvo novo entra depois do plano' do
    add(keys[:dead], 'Webhooks::WhatsappEventsJob', 'target')
    inspected = plan
    add(keys[:dead], 'Webhooks::WhatsappEventsJob', 'late-target')

    expect { apply(inspected[:inventory_hash]) }.to raise_error(described_class::Blocked, 'INVENTORY_CHANGED')

    expect(with_redis { |conn| conn.zcard(keys[:dead]) }).to eq(2)
  end

  it 'bloqueia classe desconhecida no dead set' do
    add(keys[:dead], 'OutroJob', 'unknown')
    inspected = plan

    expect { apply(inspected[:inventory_hash]) }.to raise_error(
      described_class::Blocked, 'UNKNOWN_DEAD_CLASS:OutroJob'
    )
  end

  it 'bloqueia data ingress em scheduled/retry' do
    add(keys[:retry], 'Webhooks::WhatsappEventsJob', 'retry-target')
    inspected = plan

    expect { apply(inspected[:inventory_hash]) }.to raise_error(
      described_class::Blocked, 'DATA_INGRESS_SCHEDULED_OR_RETRY:Webhooks::WhatsappEventsJob'
    )
    expect(with_redis { |conn| conn.zcard(keys[:retry]) }).to eq(1)
  end

  it 'recusa apply sem writers parados ou confirmação exata' do
    add(keys[:dead], 'Webhooks::WhatsappEventsJob', 'target')
    inspected = plan

    expect do
      described_class.apply(
        expected_hash: inspected[:inventory_hash], confirmation: 'APPLY:errado',
        writers_stopped: true, keys: keys
      )
    end.to raise_error(described_class::Blocked, 'CONFIRMATION_REQUIRED')

    expect do
      described_class.apply(
        expected_hash: inspected[:inventory_hash],
        confirmation: "APPLY:#{inspected[:inventory_hash]}", writers_stopped: false, keys: keys
      )
    end.to raise_error(described_class::Blocked, 'WRITERS_NOT_STOPPED')
  end
end
# rubocop:enable RSpec/MultipleExpectations
