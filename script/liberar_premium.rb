# frozen_string_literal: true

# Liberação de features premium do Chatwoot fazer.ai (CE fork)
# Uso: bundle exec rails runner script/liberar_premium.rb

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

puts '==> Configurando INSTALLATION_PRICING_PLAN=enterprise'
ic = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
ic.value = 'enterprise'
ic.locked = true
ic.save!

ac = InstallationConfig.find_or_initialize_by(name: 'CREATE_NEW_ACCOUNT_FROM_DASHBOARD')
ac.value = true
ac.locked = false
ac.save!

puts "    pricing_plan=#{ChatwootHub.pricing_plan}"
puts "    enterprise?=#{ChatwootApp.enterprise?}"
puts "    self_hosted_enterprise?=#{ChatwootApp.self_hosted_enterprise?}"

if Account.none?
  puts '==> Nenhuma conta encontrada — criando conta + SuperAdmin de desenvolvimento'
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
Account.find_each do |account|
  available = PREMIUM_FEATURES.select do |name|
    Account::FEATURE_LIST.any? { |f| f['name'] == name }
  end
  account.enable_features!(*available)
  account.custom_attributes['plan_name'] = 'Enterprise'
  account.save!
  enabled = account.enabled_features.keys.sort
  puts "    conta #{account.id} (#{account.name}): #{enabled.join(', ')}"
end

puts '==> Feito'
puts
puts 'NOTA: Kanban e Internal Chat Pro NÃO estão neste repo CE.'
puts '      Eles exigem o fork privado fazer-ai/chatwoot-pro / assinatura Pro.'
puts '      Internal Chat base (canais públicos, DMs) já vem no CE sem flag.'
