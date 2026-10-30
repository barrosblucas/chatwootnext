# Reuso de atendimento existente na criação em inbox marcada (micro passo 1b).
# "Abrir existente (Recomendado)": se o par (inbox, contato) já tem conversa
# não-terminal, o POST create reutiliza a existente autorizada em vez de criar
# outra (que violaria o índice parcial inbox+contato e gerava o 404 com
# rollback). Interceptor prepended no ConversationBuilder (instalado só em
# teste G0 via Installer): roda DEPOIS dos before_actions nativos (conta,
# inbox, contact, contact_inbox resolvidos e inbox show? autorizada) e ANTES
# do create_new_conversation/after_create, sob o mesmo advisory lock por par
# do fluxo canônico de transferência, para não correr com begin!/commit_local!
# nem com o IncomingHook.
# Nunca encerra/transfere implicitamente: NENHUM update de escopo aqui.
# Inbox não marcada: comportamento nativo (segue sem reuso).
# Se o par tem atendimento mas o ator não tem leitura: 403 genérico do Denied,
# sem vazar ID/dados, sem criar conversa. Com mensagem no reuso sem write?:
# 403, nada criado/enviado (o envio segue o dispatch guard da conversa).
module Connecta::Scope::ConversationReuse
  # Advisory lock por par (inbox, contato): mesma chave canônica do
  # LocalTransaction.lock! — quem decide a origem é o lock do par.
  def self.lock!(inbox_id:, contact_id:)
    Connecta::Transfer::LocalTransaction.lock!(inbox_id: inbox_id, contact_id: contact_id)
  end

  # Devolve a conversa existente reutilizável, ou nil quando deve criar nova.
  # Levanta Connecta::Scope::Denied (:forbidden) quando existe atendimento mas
  # o ator não tem leitura nele — sem revelar ID/dados (o controller renderiza
  # a mensagem genérica do Denied). Retorna nil fora de inbox marcada.
  def self.resolve(user:, inbox:, contact:)
    return nil unless Connecta::Scope::Projection.marked?(inbox.id)

    scope = Connecta::Scope::ConversationScope
            .where(inbox_id: inbox.id, contact_id: contact.id,
                   state: Connecta::Scope::ConversationScope::NON_TERMINAL_STATES)
            .order(updated_at: :desc)
            .first
    return nil if scope.nil?

    conversation = Conversation.find_by(id: scope.conversation_id)
    raise Connecta::Scope::Denied, :forbidden if conversation.nil?
    raise Connecta::Scope::Denied, :forbidden unless readable_by?(user, conversation)

    conversation
  end

  # Leitura autorizada pelo Gate (audita). O envio inicial na conversa
  # reutilizada continua exigindo write? — verificado pelo interceptor:
  # sem autoridade de escrita, nenhuma mensagem é criada.
  def self.readable_by?(user, conversation)
    Connecta::Scope::Gate.new(user).read?(conversation, access_path: 'conversation_reuse')
  end

  def self.writable_by?(user, conversation)
    Connecta::Scope::Gate.new(user).write?(conversation, access_path: 'conversation_reuse_message')
  end

  # Interceptor do ConversationBuilder#perform: com contact_inbox resolvido
  # pelos before_actions nativos, toma o lock do par e reutiliza o atendimento
  # autorizado (sem criar nova conversa, sem tocar escopos). Sem existente ou
  # fora de inbox marcada: super (fluxo nativo). Com mensagem no reuso sem
  # write?: Denied 403 antes de qualquer criação.
  module BuilderInterceptor
    def perform
      existing = find_reusable_conversation
      return existing unless existing.nil?

      super
    end

    private

    # Lock do par + lookup read-only sob o lock; nil = segue fluxo nativo.
    # Com mensagem no reuso sem write?: Denied 403 antes de qualquer criação.
    def find_reusable_conversation # rubocop:disable Metrics/CyclomaticComplexity
      ci = @contact_inbox
      inbox = ci&.inbox
      return nil unless ci && inbox && Connecta::Scope::Projection.marked?(inbox.id)

      Connecta::Scope::ConversationReuse.lock!(inbox_id: inbox.id, contact_id: ci.contact_id)
      existing = Connecta::Scope::ConversationReuse.resolve(user: Current.user, inbox: inbox, contact: ci.contact)
      return nil if existing.nil?
      return existing if params[:message].blank?
      return existing if Connecta::Scope::ConversationReuse.writable_by?(Current.user, existing)

      raise Connecta::Scope::Denied, :forbidden
    end
  end
end
