class Connecta::Runtime::CacheRevocation
  def self.scope!(scope)
    conversation = Conversation.find(scope.conversation_id)
    unit_path = Connecta::OrgUnit.find_by(id: scope.org_unit_id)&.path
    readers = Connecta::UserGrant.joins(:org_unit)
                                 .where(permission: %w[acompanhar atender admin_nominal], connecta_org_units: { enabled: true })
    readers = readers.where('connecta_org_units.path LIKE ?', "#{unit_path}%") if unit_path.present?
    user_ids = readers.distinct.pluck(:user_id)
    User.where(id: user_ids).pluck(:pubsub_token).compact_blank.uniq.each do |token|
      ActionCable.server.broadcast(token, {
                                     event: 'scope.revoked',
                                     data: {
                                       conversation_id: conversation.display_id, inbox_id: conversation.inbox_id,
                                       account_id: conversation.account_id
                                     }
                                   })
    end
  end
end
