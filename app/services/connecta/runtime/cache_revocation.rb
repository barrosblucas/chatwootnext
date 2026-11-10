class Connecta::Runtime::CacheRevocation
  # Leitores do escopo: grants acompanhar/atender/admin_nominal no setor da
  # conversa ou num ancestral (gate.rb granted_sector?), com época válida,
  # mais admins nativos same-account. Nomes de tabela via modelo: o adapter G0
  # remapeia Scope:: para as tabelas de produto em produção, então nada aqui
  # hardcode g0_*.
  def self.scope!(scope)
    conversation = Conversation.find(scope.conversation_id)
    unit_path = Connecta::Scope::OrgUnit.find_by(id: scope.org_unit_id)&.path
    user_ids = grant_reader_ids(unit_path) & verified_user_ids
    user_ids |= native_admin_ids(conversation.account_id)
    announce(conversation, user_ids)
  end

  def self.grant_reader_ids(unit_path)
    readers = Connecta::Scope::UserGrant.joins(:org_unit)
                                         .where(permission: %w[acompanhar atender admin_nominal])
                                         .merge(Connecta::Scope::OrgUnit.where(enabled: true))
    if unit_path.present?
      org_table = Connecta::Scope::OrgUnit.quoted_table_name
      path_column = Connecta::Scope::OrgUnit.connection.quote_column_name('path')
      readers = readers.where('? LIKE (? || ?)', unit_path, Arel.sql("#{org_table}.#{path_column}"), '%')
    end
    readers.distinct.pluck(:user_id)
  end

  # Gate usable?: época revogada não lê (projection verified?); nativo lê pelo
  # vínculo, sem época — o filtro vale só para leitores por grant.
  def self.verified_user_ids
    Connecta::Scope::UserAuthEpoch.where(revoked_locally_at: nil).pluck(:user_id)
  end

  def self.native_admin_ids(account_id)
    ::AccountUser.where(account_id: account_id, role: :administrator).pluck(:user_id)
  end

  def self.announce(conversation, user_ids)
    tokens = User.where(id: user_ids).pluck(:pubsub_token).compact_blank.uniq
    tokens.each do |token|
      ActionCable.server.broadcast(token, {
                                     event: 'scope.revoked',
                                     data: {
                                       conversation_id: conversation.display_id, inbox_id: conversation.inbox_id,
                                       account_id: conversation.account_id
                                     }
                                   })
    end
  end
  private_class_method :grant_reader_ids, :verified_user_ids, :native_admin_ids, :announce
end
