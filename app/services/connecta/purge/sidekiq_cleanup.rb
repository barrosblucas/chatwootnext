require 'digest'
require 'json'

# Política interna para o dead set do Sidekiq durante a janela de manutenção.
# Nunca imprime args/payload. O alvo só é removido quando a classe, o conjunto
# exato de digests do dead set e o hash de contagens batem com o plano.
class Connecta::Purge::SidekiqCleanup
  class Blocked < StandardError; end

  DISCARD_DEAD = ['Webhooks::WhatsappEventsJob'].freeze
  PRESERVE_DEAD = ['ActiveStorage::PurgeJob'].freeze
  DATA_INGRESS = ['Webhooks::WhatsappEventsJob'].freeze
  DEFAULT_KEYS = { schedule: 'schedule', retry: 'retry', dead: 'dead' }.freeze
  HASH_PATTERN = /\A[0-9a-f]{64}\z/

  class << self
    def plan(redis: nil, keys: DEFAULT_KEYS)
      data = new(redis: redis, keys: keys).snapshot
      {
        status: 'inspected',
        classes: data[:payload].slice(:scheduled, :retry, :dead),
        dead_digests: data[:payload][:dead_digests],
        inventory_hash: data[:hash]
      }
    end

    def apply(expected_hash:, confirmation:, writers_stopped:, redis: nil, keys: DEFAULT_KEYS)
      new(redis: redis, keys: keys).apply(
        expected_hash: expected_hash, confirmation: confirmation, writers_stopped: writers_stopped
      )
    end
  end

  def initialize(redis: nil, keys: DEFAULT_KEYS)
    @redis = redis
    @keys = normalize_keys(keys)
  end

  def snapshot
    with_redis do |conn|
      schedule = conn.zrange(@keys[:schedule], 0, -1)
      retry_set = conn.zrange(@keys[:retry], 0, -1)
      dead = conn.zrange(@keys[:dead], 0, -1)
      payload = {
        scheduled: counts(schedule), retry: counts(retry_set), dead: counts(dead),
        dead_digests: dead.map { |raw| digest(raw) }.sort
      }
      { payload: payload, hash: Digest::SHA256.hexdigest(JSON.generate(payload)), raw: { dead: dead } }
    end
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def apply(expected_hash:, confirmation:, writers_stopped:)
    fail!('WRITERS_NOT_STOPPED') unless writers_stopped == true
    valid_confirmation = expected_hash.to_s.match?(HASH_PATTERN) && confirmation.to_s == "APPLY:#{expected_hash}"
    fail!('CONFIRMATION_REQUIRED') unless valid_confirmation

    current = snapshot
    fail!('INVENTORY_CHANGED') unless current[:hash] == expected_hash.to_s

    payload = current[:payload]
    (payload[:scheduled].keys + payload[:retry].keys).each do |klass|
      fail!("DATA_INGRESS_SCHEDULED_OR_RETRY:#{klass}") if DATA_INGRESS.include?(klass)
    end
    payload[:dead].each_key do |klass|
      next if DISCARD_DEAD.include?(klass) || PRESERVE_DEAD.include?(klass)

      fail!("UNKNOWN_DEAD_CLASS:#{klass}")
    end

    expected_digests = payload[:dead_digests].to_set
    removed = with_redis do |conn|
      current[:raw][:dead].sum do |raw|
        next 0 unless DISCARD_DEAD.include?(job_class(raw))
        next 0 unless expected_digests.include?(digest(raw))

        conn.zrem(@keys[:dead], raw)
      end
    end

    after = snapshot
    fail!('DEAD_TARGET_REMAINS') if after[:payload][:dead].keys.any? { |klass| DISCARD_DEAD.include?(klass) }
    {
      status: 'committed',
      discarded_dead: removed,
      preserved_scheduled: after[:payload][:scheduled],
      preserved_retry: after[:payload][:retry],
      dead_after: after[:payload][:dead],
      inventory_hash: current[:hash]
    }
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  private

  def normalize_keys(keys)
    normalized = DEFAULT_KEYS.to_h { |name, default| [name, keys[name] || keys[name.to_s] || default] }
    normalized.transform_values(&:to_s).freeze
  end

  def with_redis
    return yield(@redis) if @redis

    Sidekiq.redis { |conn| yield(conn) }
  end

  def counts(rows)
    rows.each_with_object(Hash.new(0)) { |raw, result| result[job_class(raw)] += 1 }.sort.to_h
  end

  def job_class(raw)
    data = JSON.parse(raw)
    klass = data['class']
    if klass == 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper'
      args = data['args']
      return 'unknown' unless args.is_a?(Array) && args[0].is_a?(Hash)

      return args[0]['job_class'].to_s
    end
    klass.to_s
  rescue StandardError
    'unparseable'
  end

  def digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def fail!(code)
    raise Blocked, code
  end
end
