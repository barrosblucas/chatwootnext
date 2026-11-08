# Corte temporal do spike G0 (T0.3): a mensagem entrante toma o lock de (inbox, contato) e grava na conversa do escopo não terminal do par.
# O fluxo Baileys de contato individual chama set_conversation e handle_create_message sem transação própria; por isso o
# handler inteiro roda numa transação, e o lock vale até o commit da mensagem (não só até o fim de set_conversation).
module Connecta::Transfer::IncomingHook
  private

  def handle_individual_contact_message
    ActiveRecord::Base.transaction { super }
  end

  def set_conversation
    Connecta::Transfer::LocalTransaction.lock!(inbox_id: inbox.id, contact_id: @contact.id)
    scope = open_scope
    return super unless scope

    conversation = Conversation.find(scope.conversation_id)
    if conversation.resolved?
      # Compensação de borda: um callback de resolução que falhou (ou um
      # estado transitório antigo) não pode receber inbound na conversa
      # resolvida. Fecha/aborta sob o mesmo lock e só então deixa o fluxo
      # nativo criar a conversa nova; se ainda houver escopo não-terminal,
      # falha alto em vez de reabrir histórico.
      Connecta::Scope::ConversationResolution.resolve_scope!(conversation)
      scope = open_scope
      return super unless scope

      conversation = Conversation.find(scope.conversation_id)
      raise ActiveRecord::RecordNotFound, 'resolved conversation still has a non-terminal Connecta scope' if conversation.resolved?
    end

    @conversation = conversation
  end

  def open_scope
    Connecta::Scope::ConversationScope.find_by(
      inbox_id: inbox.id, contact_id: @contact.id, state: Connecta::Scope::ConversationScope::NON_TERMINAL_STATES
    )
  end
end
