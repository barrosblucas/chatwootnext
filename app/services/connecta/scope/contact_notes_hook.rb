# Prepend em Api::V1::Accounts::Contacts::NotesController (instalado só pelo spike G0).
# Notas são globais do contato e não têm etapa proprietária: contato vinculado a inbox marcada fica bloqueado para todos (404 leitura, 403 escrita).
module Connecta::Scope::ContactNotesHook
  private

  def ensure_contact
    super
    return unless Connecta::Scope::ContactVisibility.linked?(@contact)

    raise Connecta::Scope::Denied, (request.get? ? :not_found : :forbidden)
  end
end
