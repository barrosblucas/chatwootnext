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
    scope = Connecta::Scope::ConversationScope.find_by(
      inbox_id: inbox.id, contact_id: @contact.id, state: Connecta::Scope::ConversationScope::NON_TERMINAL_STATES
    )
    return super unless scope

    @conversation = Conversation.find(scope.conversation_id)
  end
end
