# Entrega só metadados a nominais capturados que ainda mantêm o grant e a sessão.
# Nativo full (I.2) NÃO entra neste canal: recebe conteúdo pelo job normal.
module Connecta::Scope::AdminMetadataDeliveryGuard
  private

  def connecta_scope_capture
    Connecta::Scope::DeliveryContext.take(self.class.name)
  end

  def perform(_tokens, event_name, data)
    context = @connecta_scope_context
    return unless valid_admin_context?(context, data)

    account = Account.find_by(id: context['account_id'])
    return unless account

    tokens = current_admin_tokens(account, context)
    return if tokens.empty?

    tokens.each { |token| ActionCable.server.broadcast(token, { event: event_name, data: data }) }
  end

  def valid_admin_context?(context, data)
    context.is_a?(Hash) && context['v'] == 1 && context['kind'] == 'admin_metadata' &&
      [data[:account_id], data['account_id']].include?(context['account_id'])
  end

  def current_admin_tokens(account, context)
    Array(context['admins']).filter_map do |user_id, role, epoch|
      user = account.users.find_by(id: user_id)
      next unless user && Connecta::Scope::DeliveryContext.epoch_same?(user.id, epoch)

      role_still_allowed?(account, user, role) ? user.pubsub_token : nil
    end
  end

  def role_still_allowed?(account, user, role)
    return false unless role == 'nominal' && Connecta::Scope::Projection.new(user).admin?

    # Revalidação no delivery: nominal que virou nativo ATUAL da conta recebe pelo canal normal;
    # metadata enfileirada antes da promoção não se retransmite obsoleta neste canal.
    !Connecta::Scope::NativeAdmin.administrator?(user, account)
  end
end
