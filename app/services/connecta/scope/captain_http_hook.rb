# Prepend em Api::V1::Accounts::Captain::AgentSessionsController e MessageReportsController (instalado só pelo spike G0).
# Leitura negada pelo Gate em inbox marcada vira 404 (decisão 002): o nativo responderia 401 e revelaria a existência.
# O hook sobrescreve authorize_conversation (em vez de um guard em before_action separado) para que a checagem do Gate
# rode antes do authorize nativo: sem leitura autorizada, o 404 sai sem passar pelo 401 do Pundit.
module Connecta::Scope::CaptainHttpHook
  def authorize_conversation
    conversation = @message&.conversation
    if conversation && current_user && Connecta::Scope::Projection.marked?(conversation.inbox_id) &&
       !Connecta::Scope::Gate.new(current_user).read?(
         conversation, access_path: "captain_#{action_name}"
       )
      raise Connecta::Scope::Denied, :not_found
    end

    super
  end
end
