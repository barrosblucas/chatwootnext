# frozen_string_literal: true

# Liberação de features premium do Chatwoot fazer.ai (CE fork)
# Local:  bundle exec rails runner script/liberar_premium.rb
# Docker: docker compose -f docker-compose.fazer.yml exec rails \
#           bundle exec rails runner /scripts/liberar_premium.rb

PREMIUM_FEATURES = %w[
  advanced_assignment
  audit_logs
  csat_review_notes
  companies
  custom_roles
  conversation_required_attributes
  disable_branding
  sla
  saml
  custom_tools
  captain_integration
  captain_integration_v2
  captain_document_auto_sync
  channel_voice
  advanced_search
].freeze

def write_installation_config(name, value, locked:)
  config = InstallationConfig.find_or_initialize_by(name: name)
  if config.respond_to?(:value=)
    config.value = value
  else
    config.val = value
  end
  config.locked = locked
  config.save!
  config
end

puts '==> Configurando INSTALLATION_PRICING_PLAN=enterprise'
write_installation_config('INSTALLATION_PRICING_PLAN', 'enterprise', locked: true)
write_installation_config('CREATE_NEW_ACCOUNT_FROM_DASHBOARD', true, locked: false)

# Limpa cache para self_hosted_enterprise? refletir o novo plano
GlobalConfig.clear_cache if defined?(GlobalConfig)

pricing = begin
  ChatwootHub.pricing_plan
rescue StandardError
  GlobalConfig.get_value('INSTALLATION_PRICING_PLAN')
end

puts "    pricing_plan=#{pricing}"
puts "    enterprise?=#{ChatwootApp.enterprise?}"
puts "    self_hosted_enterprise?=#{ChatwootApp.self_hosted_enterprise?}"

if Account.none?
  puts '==> Nenhuma conta encontrada — criando conta + SuperAdmin'
  account = Account.create!(name: 'Sua Empresa')
  user = User.new(
    name: 'Admin',
    email: 'admin@suaempresa.com',
    password: 'Password1!',
    type: 'SuperAdmin'
  )
  user.skip_confirmation!
  user.save!
  AccountUser.create!(account_id: account.id, user_id: user.id, role: :administrator)
  puts "    conta=#{account.id} login=#{user.email} / Password1!"
end

puts '==> Habilitando features premium em todas as contas'
feature_names = if defined?(Featurable::FEATURE_LIST)
                  Featurable::FEATURE_LIST.pluck('name')
                else
                  Account::FEATURE_LIST.pluck('name')
                end

Account.find_each do |account|
  available = PREMIUM_FEATURES.select { |name| feature_names.include?(name) }
  account.enable_features!(*available)
  account.custom_attributes['plan_name'] = 'Enterprise'
  account.save!
  enabled = account.enabled_features.keys.sort
  puts "    conta #{account.id} (#{account.name}): #{enabled.join(', ')}"
end

puts '==> Feito'
puts
puts 'NOTA: Kanban e Internal Chat Pro exigem chatwoot-pro / assinatura Pro.'
puts '      Internal Chat base já vem no CE sem flag.'
