# frozen_string_literal: true

# Liberação de features premium do Chatwoot fazer.ai (CE fork)
# Local:  bundle exec rails runner script/liberar_premium.rb
# Docker: docker compose -f docker-compose.fazer.yml exec rails \
#           bundle exec rails runner /scripts/liberar_premium.rb
#
# Para liberação automática de contas novas, veja watch_liberar_premium.rb.

require_relative 'premium_lib'

puts '==> Configurando INSTALLATION_PRICING_PLAN=enterprise'
PremiumLib.configurar_plano_enterprise

PremiumLib.criar_conta_inicial_se_necessario

puts '==> Habilitando features premium em todas as contas'
PremiumLib.liberar_features_premium!(verbose: true)

puts '==> Feito'
puts
puts 'NOTA: Kanban e Internal Chat Pro exigem chatwoot-pro / assinatura Pro.'
puts '      Internal Chat base já vem no CE sem flag.'
