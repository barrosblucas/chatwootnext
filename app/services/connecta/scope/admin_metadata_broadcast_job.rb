# Entrega metadados de conversa de inbox marcada a admins (plano §5.6, Q-10). Não usa ActionCableBroadcastJob: aquele job relê
# a conversa inteira nos eventos de atualização e devolveria o conteúdo ao admin.
class Connecta::Scope::AdminMetadataBroadcastJob < ApplicationJob
  queue_as :critical

  def perform(tokens, event_name, data)
    return if tokens.blank?

    tokens.each { |token| ActionCable.server.broadcast(token, { event: event_name, data: data }) }
  end
end
