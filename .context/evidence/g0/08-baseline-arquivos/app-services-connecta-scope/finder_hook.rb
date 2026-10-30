# Prepend em Conversations::PermissionFilterService (instalado só pelo spike G0). Roda antes de paginação e contagem do finder.
module Connecta::Scope::FinderHook
  def perform
    Connecta::Scope::ConversationQuery.new(super, user).perform
  end
end
