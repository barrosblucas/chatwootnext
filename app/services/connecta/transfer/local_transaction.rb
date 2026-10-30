# Transferência local do spike G0 (T0.3, T0.7a, T0.7c). A origem vai de active a transferring (begin!), depois a transferred_out (commit_local!),
# e o destino nasce pending_activation no mesmo commit. Só activate! com a versão confirmada leva o destino a active.
# Quem decide a origem é o lock de (inbox, contato), o mesmo que a mensagem entrante toma (IncomingHook).
# T0.7c: begin! estaciona os envios queued via OutboundDispatch.prepare_transfer!; com dispatching em voo o registro
# vai a awaiting_dispatch e o retorno pede espera (:wait, resume! reavalia); com uncertain a origem volta a active e o registro
# vai a aborted, e o erro é relançado (o contrato do serviço mapeia para 409). commit_local! revalida a barreira antes de
# gravar: com dispatching volta a awaiting_dispatch e devolve :wait sem commitar; com uncertain aborta e relança.
# Inbox fora de connecta_g0_scoped_inboxes não ganha comportamento de spike: sem barreira, begin! devolve :proceed.
class Connecta::Transfer::LocalTransaction # rubocop:disable Metrics/ClassLength
  class VersionMismatch < StandardError; end

  # Retorno quando há despacho em voo: WAIT pede espera (chame resume! até obter PROCEED); commit_local!
  # devolve WAIT sem commitar, ou a conversa destino criada no sucesso.
  WAIT = :wait
  HELD = :held
  PROCEED = :proceed

  attr_reader :record

  def self.lock!(inbox_id:, contact_id:)
    key = "connecta:transfer:#{inbox_id}:#{contact_id}"
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', key])
    )
  end

  def initialize(scope:, destination_org_unit:, retain_uncertain: false)
    @scope = scope
    @destination_org_unit = destination_org_unit
    @retain_uncertain = retain_uncertain
  end

  # Uma chamada só, sem a plataforma no meio: begin! e commit_local! na mesma transação. Falha em qualquer etapa desfaz tudo.
  # Se begin! pedir espera (WAIT), o commit não roda: chame resume! até obter PROCEED e só então commit_local!.
  def call(summary: 'Transferência do spike G0')
    ActiveRecord::Base.transaction do
      next WAIT unless begin! == PROCEED

      commit_local!(target_case_version: @scope.case_version + 1, summary: summary)
    end
  end

  # Origem active → transferring. Mensagens do cidadão continuam entrando na origem até o commit local.
  # Antes de voltar, estaciona os envios queued e olha os em voo: com dispatching o pedido vai a
  # awaiting_dispatch e o retorno pede espera (WAIT, resume! reavalia); com uncertain a origem volta a active,
  # o pedido vai a aborted e o erro é relançado (409 no contrato do serviço; o park interno da T0.7b já foi
  # desfeito). Sem pendência, retorna PROCEED. Idempotente sob o lock do T0.3/T0.7a.
  def begin!
    outcome = locked do
      origin = take_origin!
      begin
        settle_begin!(prepare_conversation!(origin))
      rescue Connecta::Transfer::OutboundDispatch::ConflictError => e
        @conflict = e
        handle_dispatch_conflict!
      end
    end
    return outcome unless outcome == :conflict

    raise @conflict
  end

  # Reavalia a barreira depois de um WAIT: sem dispatching/uncertain, o registro volta a requested e devolve
  # PROCEED; com dispatching em voo mantém awaiting_dispatch e devolve WAIT; com uncertain aborta o preparo
  # local, devolve a origem a active e relança o erro (409 no contrato do serviço). Idempotente.
  def resume!
    outcome = locked do
      load_open_record!
      origin = Connecta::Scope::ConversationScope.find_by(id: @scope.id)
      if resumable?(origin)
        begin
          recheck_and_settle!(origin)
        rescue Connecta::Transfer::OutboundDispatch::ConflictError => e
          @conflict = e
          handle_dispatch_conflict!
        end
      else
        PROCEED
      end
    end
    return outcome unless outcome == :conflict

    raise @conflict
  end

  # Origem transferring → transferred_out (resolvida, sem acesso). Destino nasce pending_activation, com a nota de resumo.
  # Revalida a barreira antes de gravar: sem despacho pendente/incerto, commita; com dispatching em voo volta
  # o registro a awaiting_dispatch e devolve WAIT sem commitar; com uncertain aborta o preparo local e relança
  # (409 no contrato do serviço). Depois do commit, a origem nunca reabre e o destino continua
  # pending_activation até a confirmação de versão. Idempotente: commit repetido devolve o destino criado.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def commit_local!(target_case_version:, summary:)
    outcome = locked do
      origin = Connecta::Scope::ConversationScope.find_by(id: @scope.id)
      record = load_open_record!

      if record&.state == 'committed_local'
        @destination_hit = Conversation.find(record.destination_conversation_id)
        :committed
      elsif origin.nil? || origin.state != 'transferring' || record.nil?
        raise ActiveRecord::RecordNotFound, 'preparo local ausente'
      else
        @record = record
        barrier = recheck_conversation!(origin)
        if barrier.wait
          record.update!(state: 'awaiting_dispatch')
          WAIT
        else
          origin_conversation = Conversation.find(origin.conversation_id)
          # Sem callbacks: resolver pelo modelo geraria mensagem de atividade na origem.
          # rubocop:disable Rails/SkipsModelValidations
          origin_conversation.update_column(:status, :resolved)
          # rubocop:enable Rails/SkipsModelValidations

          origin.update!(state: 'transferred_out')
          destination_conversation = open_destination(origin, origin_conversation, summary)
          record.update!(state: 'committed_local', destination_conversation_id: destination_conversation.id,
                         target_case_version: target_case_version)
          @destination_hit = destination_conversation
          :committed
        end
      end
    rescue Connecta::Transfer::OutboundDispatch::ConflictError => e
      @conflict = e
      handle_dispatch_conflict!
    end
    raise @conflict if outcome == :conflict

    outcome == :committed ? @destination_hit : outcome
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # Só antes do commit local: origem transferring → active e registro aborted. Depois do commit a busca falha e nada muda.
  # Também desiste de um preparo retido em awaiting_dispatch (origem volta a active).
  def abort!
    locked do
      Connecta::Scope::ConversationScope.find_by!(id: @scope.id, state: 'transferring').update!(state: 'active')
      load_open_record!.update!(state: 'aborted')
    end
  end

  # Só com a versão confirmada pela plataforma, igual à alvo do commit local. Outra versão é recusada sem mudar nada.
  # Idempotente: repetir com a mesma versão confirmada devolve o destino sem erro nem efeitos novos; repetir com
  # versão diferente continua recusado (VersionMismatch) sem mudar nada. Nova instância resolve o transfer pela
  # origem verificada (source_conversation_id do scope), nunca pelo "último destino".
  def activate!(case_version:)
    locked do
      record = activation_record!
      @record = record
      destination = scoped_destination(record)
      raise VersionMismatch, 'versão confirmada diferente da alvo' unless case_version == record.target_case_version

      if record.state == 'committed_local'
        require_pending_destination!(destination)
        destination.update!(state: 'active', case_version: case_version)
        record.update!(state: 'committed')
      else
        require_committed_destination!(record, destination, case_version)
      end
    end
  end

  # Divergência irrecuperável depois do commit local: o destino fica só para admin. A origem nunca volta.
  def mark_stuck!
    locked do
      record = Connecta::Transfer::TransferRecord.find_by!(id: @record.id, state: 'committed_local')
      destination_scope(record).update!(state: 'activation_stuck')
      record.update!(state: 'activation_stuck')
    end
  end

  private

  def locked
    ActiveRecord::Base.transaction do
      self.class.lock!(inbox_id: @scope.inbox_id, contact_id: @scope.contact_id)
      yield
    end
  end

  # Origem sob o lock do T0.3: active vira transferring atomizado com o pedido requested. Idempotente:
  # begin! repetido na mesma origem reutiliza o pedido aberto em vez de duplicar (o índice parcial aberto
  # só permite um por conversa de origem).
  def take_origin!
    origin = Connecta::Scope::ConversationScope.find_by(id: @scope.id)
    raise ActiveRecord::RecordNotFound, 'origem fora de active' if origin.nil?
    return reuse_open_record!(origin) if origin.state == 'transferring'
    raise ActiveRecord::RecordNotFound, 'origem fora de active' if origin.state != 'active'

    begin
      fresh = Connecta::Scope::ConversationScope.find_by!(id: origin.id, state: 'active')
      fresh.update!(state: 'transferring')
      @record = Connecta::Transfer::TransferRecord.create!(
        source_conversation_id: fresh.conversation_id, state: 'requested',
        destination_org_unit_id: @destination_org_unit.respond_to?(:id) ? @destination_org_unit.id : @destination_org_unit
      )
      fresh
    rescue ActiveRecord::RecordNotUnique
      retry_open_record!(origin)
      Connecta::Scope::ConversationScope.find_by!(id: origin.id, state: 'transferring')
    end
  end

  # Inbox marcada estaciona os envios queued e lê os em voo; inbox não marcada segue sem barreira.
  def prepare_conversation!(origin)
    return Connecta::Transfer::OutboundDispatch::Result.new(parked: 0, wait: false) unless transfer_scoped?

    Connecta::Transfer::OutboundDispatch.prepare_transfer!(Conversation.find(origin.conversation_id))
  end

  # Releitura da barreira para resume!/commit_local!: queued novo vira parked; dispatching/uncertain decidem.
  def recheck_conversation!(origin)
    return Connecta::Transfer::OutboundDispatch::Result.new(parked: 0, wait: false) unless transfer_scoped?

    Connecta::Transfer::OutboundDispatch.prepare_transfer!(Conversation.find(origin.conversation_id))
  end

  # Fecha o begin!/resume!: dispatching em voo retém em awaiting_dispatch (WAIT); sem pendência libera
  # (PROCEED). Chamado fora do rescue: ConflictError (uncertain) sobe para begin!/resume!, que desfazem o
  # preparo local e relançam (origem volta a active, pedido vai a aborted). O park interno de queued já foi
  # desfeito pela T0.7b antes de levantar.
  def settle_begin!(dispatch_result)
    return PROCEED if dispatch_result.nil? || !dispatch_result.wait

    @record.update!(state: 'awaiting_dispatch')
    WAIT
  end

  def transfer_scoped?
    Connecta::Scope::ScopedInbox.exists?(inbox_id: @scope.inbox_id)
  end

  def resumable?(origin)
    !@record.nil? && !origin.nil? && origin.state == 'transferring' && transfer_scoped?
  end

  # Releitura da barreira pós-WAIT: dispatching mantém o pedido retido (WAIT); barreira
  # liberada volta o pedido a requested (PROCEED), como na máquina do plano §7.
  def recheck_and_settle!(origin)
    settled = settle_begin!(recheck_conversation!(origin))
    @record.update!(state: 'requested') if settled == PROCEED && @record.state == 'awaiting_dispatch'
    settled
  end

  def load_open_record!
    @record = Connecta::Transfer::TransferRecord.find_by(
      source_conversation_id: @scope.conversation_id,
      state: %w[requested awaiting_dispatch prepared unknown committed_local]
    )
  end

  def retry_open_record!(_origin)
    load_open_record!
    raise ActiveRecord::RecordNotUnique, 'pedido aberto de outra origem' if @record.nil?

    @record.update!(state: 'requested') if @record.state == 'awaiting_dispatch'
  end

  # begin! repetido com a origem já em transferring: reutiliza o pedido aberto da mesma origem.
  def reuse_open_record!(origin)
    load_open_record!
    raise ActiveRecord::RecordNotFound, 'preparo local ausente' if @record.nil?

    @record.update!(state: 'requested') if @record.state == 'awaiting_dispatch'
    Connecta::Scope::ConversationScope.find_by!(id: origin.id, state: 'transferring')
  end

  # Desfaz o preparo local retido pelo uncertain: origem transferring volta a active e pedido vai a aborted.
  # Roda dentro do rescue de ConflictError, já fora da subtransação desfeita pela T0.7b. Não toca @record
  # quando o pedido já saiu dos estados abertos (commit já gravado nunca reabre).
  def abort_open_record!
    Connecta::Scope::ConversationScope.find_by(id: @scope.id, state: 'transferring')&.update!(state: 'active')
    @record.update!(state: 'aborted') if @record&.persisted? && %w[requested awaiting_dispatch prepared unknown].include?(@record.state)
    @record
  end

  # Production summary transfers retain the cut while an outbound result is uncertain; legacy G0 callers keep
  # the original abort behavior. The operator reconciles the dispatch, then the same transfer can resume.
  def handle_dispatch_conflict!
    return abort_open_record! && :conflict unless @retain_uncertain

    @record.update!(state: 'awaiting_dispatch') if @record&.persisted? && %w[requested awaiting_dispatch prepared].include?(@record.state)
    :held
  end

  # A origem já saiu dos estados não terminais antes deste INSERT: o índice único de (inbox, contato) não deixa dois.
  def open_destination(origin, origin_conversation, summary)
    destination_conversation = Conversation.create!(origin_conversation.slice(:account_id, :inbox_id, :contact_id, :contact_inbox_id))
    Connecta::Scope::ConversationScope.create!(
      conversation_id: destination_conversation.id, inbox_id: origin.inbox_id, contact_id: origin.contact_id,
      org_unit: @destination_org_unit, state: 'pending_activation', case_protocol: origin.case_protocol, case_version: 0
    )
    Message.create!(
      account_id: destination_conversation.account_id, inbox_id: destination_conversation.inbox_id,
      conversation: destination_conversation, message_type: :outgoing, private: true,
      content: "Transferido de #{origin.org_unit.name} · protocolo #{origin.case_protocol} · " \
               "#{Time.current.strftime('%d/%m/%Y %H:%M')}\n\nResumo: #{summary}"
    )
    destination_conversation
  end

  def destination_scope(record)
    Connecta::Scope::ConversationScope.find_by!(conversation_id: record.destination_conversation_id, state: 'pending_activation')
  end

  # Repetição idempotente do activate!: a referência verificada é o transfer da origem (scope), nunca o
  # "último destino". Vale para a mesma instância (@record) e para instância nova (outro LocalTransaction
  # para o mesmo scope, quando a API de serviço permitir). Versão diferente continua recusada antes de
  # qualquer escrita (VersionMismatch); registro ambíguo ou fora de committed_local/committed falha fechado.
  def activation_record!
    scoped = Connecta::Transfer::TransferRecord.where(source_conversation_id: @scope.conversation_id, state: %w[committed_local committed]).to_a
    raise ActiveRecord::RecordNotFound, 'transferência da origem não encontrada' if scoped.size != 1

    record = scoped.first
    raise ActiveRecord::RecordNotFound, 'transferência da origem não encontrada' if !@record.nil? && !@record.id.nil? && @record.id != record.id

    record
  end

  def scoped_destination(record)
    Connecta::Scope::ConversationScope.find_by!(conversation_id: record.destination_conversation_id)
  end

  # Primeira ativação: o destino precisa ser o desta transferência, ainda pendente, sem versão gravada.
  def require_pending_destination!(destination)
    valid = destination.state == 'pending_activation' && destination.case_version.zero? &&
            destination_matches_scope?(destination)
    raise ActiveRecord::RecordNotFound, 'destino da transferência não encontrado' unless valid
  end

  # Repetição idempotente: o destino precisa ser o desta transferência, já ativo, com a mesma versão.
  def require_committed_destination!(record, destination, case_version)
    valid = destination.state == 'active' && destination.case_version == case_version &&
            destination.case_version == record.target_case_version && destination_matches_scope?(destination)
    raise ActiveRecord::RecordNotFound, 'destino da transferência não encontrado' unless valid
  end

  def destination_matches_scope?(destination)
    destination.inbox_id == @scope.inbox_id && destination.contact_id == @scope.contact_id
  end
end
