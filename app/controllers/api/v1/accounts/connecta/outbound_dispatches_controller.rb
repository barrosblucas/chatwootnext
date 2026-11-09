class Api::V1::Accounts::Connecta::OutboundDispatchesController < Api::V1::Accounts::BaseController
  before_action :authorize_nominal_admin!

  def index
    rows = Connecta::OutboundDispatch.joins(:conversation)
                                     .where(state: %w[parked uncertain], conversations: { account_id: Current.account.id })
                                     .order(:created_at).limit(100)
    render json: { dispatches: rows.map { |row| serialize(row) } }
  end

  # Resolução de despacho com validação de estado e auditoria em uma ação; dividir espalha a checagem.
  def resolve # rubocop:disable Metrics/AbcSize
    dispatch = Connecta::OutboundDispatch.joins(:conversation)
                                         .find_by!(id: params[:id], conversations: { account_id: Current.account.id })
    state = params.require(:state).to_s
    connector_message_id = params[:connector_message_id].to_s.presence
    unless state == 'failed' || (state == 'accepted' && connector_message_id.present?)
      render json: { error: 'Choose accepted with a connector id, or failed.' }, status: :unprocessable_entity
      return
    end
    raise ActiveRecord::RecordNotFound unless dispatch.state == 'uncertain'

    dispatch.update!(state: state, connector_message_id: connector_message_id, resolved_at: Time.current, resolved_by: current_user.id)
    Connecta::AccessAudit.create!(
      user_id: current_user.id, conversation_id: dispatch.conversation_id,
      surface: 'outbound_dispatch', access_path: 'admin', decision: 'allow'
    )
    render json: serialize(dispatch)
  end

  private

  def authorize_nominal_admin!
    raise Pundit::NotAuthorizedError unless Connecta::Scope::Projection.new(current_user).admin?
  rescue Pundit::NotAuthorizedError
    # 403 local (sem tocar o handler global, que segue 401): o frontend só
    # suprime 403, então o agente vinculado não recebe popup enganoso.
    # Autenticado sem admin_nominal cai aqui; não autenticado cai no
    # authenticate_user! (401) antes deste filtro.
    render json: { error: 'Admin nominal permission required' }, status: :forbidden
  end

  def serialize(row)
    { id: row.id, conversation_id: row.conversation.display_id, message_id: row.message_id,
      state: row.state, attempted_at: row.attempted_at, connector_message_id: row.connector_message_id }
  end
end
