# frozen_string_literal: true

# Libera features premium automaticamente para contas novas.
# Roda em loop dentro do container (serviço premium_watch do compose):
#   docker compose -f docker-compose.fazer.yml exec premium_watch \
#     bundle exec rails runner /scripts/watch_liberar_premium.rb
#
# Idempotente e tolerante a falhas: a cada ciclo varre as contas e habilita
# as features premium + plan_name=Enterprise nas que ainda não têm.

require_relative 'premium_lib'

$stdout.sync = true

WATCH_INTERVAL_SECONDS = Integer(ENV.fetch('PREMIUM_WATCH_INTERVAL', '60'))

puts "[premium_watch] iniciado (intervalo=#{WATCH_INTERVAL_SECONDS}s)"

loop do
  begin
    PremiumLib.liberar_features_premium!
    puts "[premium_watch] ciclo ok (#{Time.current.strftime('%H:%M:%S')})"
  rescue StandardError => e
    puts "[premium_watch] erro no ciclo: #{e.class}: #{e.message}"
  end
  sleep WATCH_INTERVAL_SECONDS
end
