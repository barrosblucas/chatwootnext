# Fila Bot (somente leitura, servidor): conversas abertas autorizadas com triagem
# ativa no bot e sem protocolo. Dois consumidores com seleções distintas:
# - caminho dedicado (`perform`): pré-filtro local (reception, sem protocolo,
#   versão 0) + subconjunto elegível confirmado pela plataforma; até 300
#   candidatos em 3 lotes de 100, timeout de 5 s por lote; falha fechada com
#   Unavailable (503), nunca parcial;
# - exclusão opt-in da fila humana (`exclude_from`): puramente local, sem rede.
#   Nas inboxes marcadas só permanece atendimento corrente e roteado (escopo
#   `active` do mesmo par, protocolo não-branco, unidade habilitada); qualquer
#   falha de banco preserva a lista original e sinaliza `unavailable: true`.
class Connecta::Scope::BotEligibility
  class Unavailable < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super("Connecta bot list unavailable (#{code})")
    end
  end

  # Teto da plataforma por requisição: acima de 100 pares o WP devolve 400.
  BATCH_SIZE = 100
  # Caminho dedicado: no máximo 3 lotes sequenciais por observação. Cada lote tem
  # o timeout próprio do PlatformClient (5 s), então o pior caso fica em ~15 s +
  # overhead em vez de crescer com a conta; acima disso a fila responde 503
  # (overflow) em vez de truncar — truncar seria indistinguível de "sem Bot".
  MAX_CANDIDATES = 300

  OVERFLOW_CODE = 'bot_eligibility_overflow'.freeze
  UNAVAILABLE_CODE = 'bot_eligibility_unavailable'.freeze

  # Prova de filtragem segura para o caminho dedicado: opt-in do runtime +
  # ramo bot instalado no finder. Sem isso o finder nativo ignoraria
  # conversation_type=bot e devolveria a fila geral como se fosse elegível.
  def self.available?
    Connecta::Runtime::Feature.enabled? &&
      (ConversationFinder <= Connecta::Scope::ConversationFinderHook) == true
  end

  # Exclusão opt-in da fila humana: estreita a relação autorizada, antes de
  # contagens e paginação, ao atendimento corrente e roteado nas inboxes
  # marcadas (escopo `active` do mesmo par conversation+inbox, protocolo
  # não-branco, unidade vinculada habilitada). Recepção sem protocolo (Bot, com
  # ou sem caso vigente no WP), `pending_activation`/`transferring`/
  # `activation_stuck` (protocolo commitido com ativação local pendente: nem Bot
  # nem humano) e conversas legadas sem escopo somem desta visão marcada;
  # inboxes não-marcadas passam intactas. Sem rede: a partição positiva local é
  # suficiente porque nenhum candidato Bot (`reception`/nulo/versão 0) satisfaz
  # o predicado humano, e o caminho Bot dedicado segue com confirmação WP e
  # 503 explícito. Nunca levanta: erro de banco devolve a relação original com
  # `unavailable: true`; sem erro, `unavailable` é sempre `false`.
  def self.exclude_from(relation)
    return { relation: relation, unavailable: true } unless available?

    marked_ids = Connecta::Scope::Projection.marked_inbox_ids
    return { relation: relation, unavailable: false } if marked_ids.empty?

    { relation: human_only(relation, marked_ids), unavailable: false }
  rescue ActiveRecord::ActiveRecordError
    { relation: relation, unavailable: true }
  end

  # Fila humana marcada = atendimento ativo corrente. EXISTS correlacionado ao
  # par atual para linhas e contagens saírem da mesma relação, sem lista em
  # memória e sem ampliar conta, inbox ou grant da relação de entrada.
  def self.human_only(relation, marked_ids)
    scope_table = Conversation.connection.quote_table_name(Connecta::Scope::ConversationScope.table_name)
    unit_table = Conversation.connection.quote_table_name(Connecta::Scope::OrgUnit.table_name)
    relation.where.not(inbox_id: marked_ids).or(
      relation.where(
        "EXISTS (SELECT 1 FROM #{scope_table} human_scope " \
        "INNER JOIN #{unit_table} human_unit " \
        'ON human_unit.id = human_scope.org_unit_id AND human_unit.enabled = TRUE ' \
        'WHERE human_scope.conversation_id = conversations.id ' \
        'AND human_scope.inbox_id = conversations.inbox_id ' \
        "AND human_scope.state = 'active' " \
        "AND NULLIF(BTRIM(human_scope.case_protocol), '') IS NOT NULL)"
      )
    )
  end

  # Só conversa aberta, já autorizada pela relação de entrada (conta + inboxes do
  # agente, aplicadas pelo finder), com escopo Connecta em recepção, sem protocolo
  # e versão 0. Resolvidas, não-Connecta, com protocolo ou fora da permissão nunca
  # entram; par fora da relação nunca é enviado. Ordem estável por id para lotes
  # determinísticos. Sem rede quando não há candidato (lista não-Connecta).
  def self.candidate_pairs(relation, limit)
    quoted = Conversation.connection.quote_table_name(Connecta::Scope::ConversationScope.table_name)
    relation
      .where(status: :open)
      .joins("INNER JOIN #{quoted} bot_scope ON bot_scope.conversation_id = conversations.id " \
             'AND bot_scope.inbox_id = conversations.inbox_id')
      .where(bot_scope: { state: 'reception' })
      .where(bot_scope: { case_protocol: nil })
      .where(bot_scope: { case_version: 0 })
      .reorder('conversations.id ASC')
      .limit(limit)
      .pluck('conversations.inbox_id', 'conversations.id')
      .uniq
  end

  # Subconjunto elegível na ordem estável da observação local (id ASC), não na
  # ordem da plataforma: paginação estável independente da ordem devolvida.
  def self.eligible_ids(pairs, client)
    eligible = Set.new
    pairs.each_slice(BATCH_SIZE) do |batch|
      parsed = client.bot_eligibility(batch.map { |(inbox_id, id)| { inbox_id: inbox_id, conversation_id: id } })
      validate_batch!(parsed, batch, eligible)
    end
    pairs.select { |(inbox_id, id)| eligible.include?("#{inbox_id}:#{id}") }.map(&:last)
  end

  # Validação estrita ponto a ponto: forma, tipos, pertencimento ao lote enviado
  # e ausência de duplicatas (inclusive entre lotes). Qualquer desvio invalida a
  # observação inteira — nunca resultado parcial.
  def self.validate_batch!(parsed, batch, eligible)
    sent = batch.to_set { |(inbox_id, id)| "#{inbox_id}:#{id}" }
    eligible_entries!(parsed).each do |entry|
      key = strict_key!(entry)
      raise Unavailable, UNAVAILABLE_CODE unless sent.include?(key) && eligible.add?(key)
    end
  end

  # Envelope: só Array em eligible (string ou símbolo); resto é indisponível.
  def self.eligible_entries!(parsed)
    entries = parsed.is_a?(Hash) ? (parsed['eligible'] || parsed[:eligible]) : nil
    raise Unavailable, UNAVAILABLE_CODE unless entries.is_a?(Array)

    entries
  end

  # Inteiro positivo estrito: forma ou tipo errado é indisponível.
  def self.positive_integer?(value)
    value.is_a?(Integer) && value.positive?
  end

  # Par estrito: ids inteiros positivos; forma ou tipo errado é indisponível.
  def self.strict_key!(entry)
    raise Unavailable, UNAVAILABLE_CODE unless entry.is_a?(Hash)

    inbox_id = entry['inbox_id'] || entry[:inbox_id]
    conversation_id = entry['conversation_id'] || entry[:conversation_id]
    raise Unavailable, UNAVAILABLE_CODE unless positive_integer?(inbox_id) && positive_integer?(conversation_id)

    "#{inbox_id}:#{conversation_id}"
  end

  def initialize(relation)
    @relation = relation
  end

  def perform
    pairs = self.class.candidate_pairs(@relation, MAX_CANDIDATES + 1)
    raise Unavailable, OVERFLOW_CODE if pairs.size > MAX_CANDIDATES
    return @relation.where(id: []) if pairs.empty?

    @relation.where(id: self.class.eligible_ids(pairs, Connecta::Runtime::PlatformClient.new))
  rescue ActiveRecord::ActiveRecordError, Connecta::Runtime::PlatformClient::Error
    raise Unavailable, UNAVAILABLE_CODE
  end
end
