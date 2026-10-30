# frozen_string_literal: true

# Guarda do alvo F5 (nome do módulo legado G0). rails_helper só define métodos: nada roda até
# route_inventory_spec.rb chamar verify! antes de `require 'rails_helper'`.
# Recusa a execução fora de `scripts/connecta/g0_test_env.sh --spec`, sem boot Rails e sem ler arquivos Dotenv.
module Connecta
end

module Connecta::G0TargetGuard
  module_function

  def verify!
    problems = environment_problems + dotenv_problems
    return if problems.empty?

    abort("F5 guard: execução recusada antes do Rails:\n- #{problems.join("\n- ")}\n" \
          'Use scripts/connecta/g0_test_env.sh --spec --apply (exige autorização humana).')
  end

  def environment_problems
    expected = {
      'RAILS_ENV' => 'test',
      'CONNECTA_G0_RUNNER' => 'conecta-consolidacao-20261029-f5',
      'POSTGRES_HOST' => '127.0.0.1',
      'POSTGRES_PORT' => '55439',
      'POSTGRES_USERNAME' => 'postgres',
      'POSTGRES_DATABASE' => 'conecta_consolidacao_20261029_f5',
      'REDIS_URL' => 'redis://127.0.0.1:56389/0'
    }
    problems = expected.reject { |key, value| ENV[key] == value }.keys.map { |key| "#{key} fora do alvo F5" }
    problems << 'POSTGRES_PASSWORD ausente (autenticação obrigatória)' if ENV['POSTGRES_PASSWORD'].to_s.empty?
    problems << 'REDIS_PASSWORD ausente (autenticação obrigatória)' if ENV['REDIS_PASSWORD'].to_s.empty?
    problems << 'DATABASE_URL definida (poderia redirecionar o banco)' if ENV.key?('DATABASE_URL')
    problems
  end

  # Só checa existência pelo nome: o conteúdo nunca é lido.
  def dotenv_problems
    root = File.expand_path('../../..', __dir__)
    Dir.glob(File.join(root, '.env*'))
       .reject { |path| path.end_with?('.example') }
       .map { |path| "arquivo Dotenv na raiz (seria lido pelo Rails): #{File.basename(path)}" }
  end
end
