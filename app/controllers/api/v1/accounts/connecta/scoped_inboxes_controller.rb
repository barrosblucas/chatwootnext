# T3.9: alternância do modo de contenção por inbox escopada. Só admin
# nominal (projeção), com auditoria append-only. Pundit::NotAuthorizedError
# vira 403 pelo handle_with_exception nativo (mesmo padrão dos demais
# controllers Connecta). Fora da projeção admin, nada é revelado: inbox sem
# marca responde 404.
class Api::V1::Accounts::Connecta::ScopedInboxesController < Api::V1::Accounts::BaseController
  def update
    raise Pundit::NotAuthorizedError unless Connecta::Scope::Projection.new(current_user).admin?

    inbox = ::Inbox.find_by!(id: params[:inbox_id], account_id: params[:account_id])
    scoped = Connecta::Scope::ScopedInbox.find_or_initialize_by(inbox_id: inbox.id)
    scoped.update!(enforcement: params.require(:enforcement).to_s)
    Connecta::Scope::AccessAudit.create!(
      user_id: current_user.id, conversation_id: nil, surface: 'scoped_inbox',
      access_path: 'enforcement_update', decision: 'allow'
    )
    render json: { inbox_id: scoped.inbox_id, enforcement: scoped.enforcement }
  rescue Pundit::NotAuthorizedError
    render json: { error: 'Admin nominal permission required' }, status: :forbidden
  end
end
