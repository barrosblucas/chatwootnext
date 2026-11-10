# Bloqueio de troca de senha para agentes gerenciados pelo Facilita Saúde.
# Gerenciado = AccountUser em CONNECTA_ACCOUNT_ID com papel `agent`, sem
# privilégio (não SuperAdmin e sem `administrator` em nenhuma conta).
# Administradores e SuperAdmins nunca são afetados; o endpoint HMAC de
# provisionamento (`set_password`) continua funcionando (não passa por aqui).
module Connecta::Runtime::PasswordGuard
  MANAGED_MESSAGE = 'Sua senha é gerenciada pelo Facilita Saúde. Troque em Facilita Saúde → Minha conta.'.freeze

  class << self
    def managed?(user)
      return false if user.nil?

      account_id = connecta_account_id
      return false if account_id.nil?

      membership = user.account_users.find_by(account_id: account_id)
      return false unless membership&.agent?
      return false if user.type == 'SuperAdmin'
      return false if user.account_users.exists?(role: :administrator)

      true
    end

    private

    def connecta_account_id
      raw = ENV.fetch('CONNECTA_ACCOUNT_ID', nil)
      id = Integer(raw, 10)
      id.positive? ? id : nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
