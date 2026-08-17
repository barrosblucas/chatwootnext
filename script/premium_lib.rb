# frozen_string_literal: true

# Lógica compartilhada de liberação premium (fazer.ai CE fork).
# Usada por liberar_premium.rb (manual) e watch_liberar_premium.rb (automático).

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

module PremiumLib
  module_function

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

  def configurar_plano_enterprise
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
  end

  def criar_conta_inicial_se_necessario
    return unless Account.none?

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

  def feature_names_disponiveis
    if defined?(Featurable::FEATURE_LIST)
      Featurable::FEATURE_LIST.pluck('name')
    else
      Account::FEATURE_LIST.pluck('name')
    end
  end

  # Libera features premium + plan_name=Enterprise em TODAS as contas.
  # Idempotente: só adiciona features que ainda não estão habilitadas.
  def liberar_features_premium!(verbose: false)
    feature_names = feature_names_disponiveis
    available = PREMIUM_FEATURES.select { |name| feature_names.include?(name) }

    Account.find_each do |account|
      enabled_before = account.enabled_features.keys
      account.enable_features!(*available)
      account.custom_attributes['plan_name'] = 'Enterprise'
      account.save!
      enabled = account.enabled_features.keys.sort
      new_features = enabled - enabled_before

      next if new_features.empty? && !verbose

      puts "    conta #{account.id} (#{account.name}): #{enabled.join(', ')}"
    end
  rescue StandardError => e
    puts "    ERRO ao liberar features: #{e.class}: #{e.message}"
    raise e if defined?(Rails) && Rails.env.test?

    nil
  end
end
