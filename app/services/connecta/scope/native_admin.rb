# Administrador nativo da conta (Chatwoot): associação ATUAL AccountUser com role
# administrator na conta do recurso. Sem grant setorial (admin_nominal), sem cache,
# sem papel global: cada chamada reconsulta o vínculo no banco, então rebaixamento
# ou remoção de membership nega na requisição seguinte. Reaproveitável por HTTP e
# realtime (I.2) via o mesmo predicado.
module Connecta::Scope::NativeAdmin
  module_function

  # Prova account-scoped: usuário é administrator da conta informada AGORA.
  def administrator?(user, account)
    return false if user.nil? || account.nil?

    account_id = account.is_a?(Account) ? account.id : account
    user_id = user.is_a?(User) ? user.id : user
    return false if account_id.nil? || user_id.nil?

    ::AccountUser.exists?(account_id: account_id, user_id: user_id, role: :administrator)
  end

  # Resolve a conta do recurso (conversa) a partir do registro vivo, sem confiar
  # em parâmetro/cabeçalho forjado. Retorna nil quando a conversa não existe.
  def account_id_of_conversation(conversation)
    conversation&.account_id
  end

  # Nativo full same-account: vínculo atual na conta DA CONVERSA. Recurso de
  # outra conta nunca libera, mesmo com admin na conta A.
  def authorized_for?(user, conversation)
    account_id = account_id_of_conversation(conversation)
    return false if account_id.nil?

    administrator?(user, account_id) && conversation_in_account?(conversation, account_id)
  end

  def conversation_in_account?(conversation, account_id)
    conversation.account_id == account_id
  end
end
