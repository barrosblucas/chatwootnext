# Negação HTTP do spike G0 para usuário autenticado (404 na leitura, 403 na escrita e na criação, 409 em manutenção, 422 em team_id proibido).
# Renderizada só pelos controllers do spike.
class Connecta::Scope::Denied < StandardError
  MESSAGES = {
    not_found: 'Resource could not be found',
    forbidden: 'You are not authorized to do this action',
    conflict: 'Human-number inbox is in maintenance',
    unprocessable_entity: 'Team assignment is not allowed in this inbox'
  }.freeze

  attr_reader :status

  def initialize(status)
    @status = status
    super(MESSAGES.fetch(status))
  end
end
