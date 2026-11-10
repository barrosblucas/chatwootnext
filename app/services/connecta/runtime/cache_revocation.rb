class Connecta::Runtime::CacheRevocation
  def self.scope!(scope)
    conversation = Conversation.find(scope.conversation_id)
    unit_path = Connecta::Scope::OrgUnit.find_by(id: scope.org_unit_id)&.path
    readers = Connecta::Scope::UserGrant.joins(:org_unit)
                                        .where(permission: %w[acompanhar atender admin_nominal],
                                               connecta_g0_org_units: { enabled: true })
    # O gate libera o grant cujo setor é o da conversa ou um ancestral dele
    # (gate.rb granted_sector?): o caminho do grant é prefixo do caminho da
    # unidade, não o contrário.
    readers = readers.where('? LIKE (connecta_g0_org_units.path || ?)', unit_path, '%') if unit_path.present?
    user_ids = readers.distinct.pluck(:user_id)
    # Admin nativo same-account lê tudo (gate.rb native_admin_authorized?):
    # também precisa do scope.revoked para limpar a contagem.
    user_ids |= ::AccountUser.where(account_id: conversation.account_id, role: :administrator).pluck(:user_id)
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
