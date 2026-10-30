# Evidência 18 · T0.7c integração transferência ↔ despacho em voo (spike G0)

Data: 2026-10-24. Worktree: `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`.

**Estado: CÓDIGO (NÃO VALIDADO).** Nenhum spec foi executado nesta tarefa, por instrução do humano ("executar tudo, completo ...
depois vamos testando"). Não há run, log de spec, RuboCop executado, nem validação de sintaxe além de `git diff --check`.
A validação (specs T0.7 + RuboCop + regressões) é tarefa posterior da fase, ainda pendente.

## 1. O que foi implementado (código, sem prova)

- `app/services/connecta/transfer/local_transaction.rb`: completa a T0.7c.
  - `take_origin!`: origem `active → transferring` sob o lock de (inbox, contato) do T0.3, atomizado com o pedido
    `TransferRecord` em `requested`. Idempotente: `begin!` repetido na mesma origem reutiliza o pedido aberto
    (índice parcial aberto só permite um por conversa de origem; `RecordNotUnique` recai em `retry_open_record!`).
  - `prepare_conversation!(origin)`: inbox marcada ⇒ `OutboundDispatch.prepare_transfer!` (contrato estável da T0.7b,
    não reescrito: parka `queued`, `wait=true` com `dispatching` em voo, `ConflictError` com `uncertain`);
    inbox não marcada ⇒ sem barreira (`Result(parked: 0, wait: false)`), sem comportamento de spike.
  - `settle_begin!(result)`: `wait=true` ⇒ pedido vai a `awaiting_dispatch`, retorno `WAIT` (`:wait`, `resume!` reavalia);
    sem pendência ⇒ `PROCEED` (`:proceed`). `ConflictError` sobe para `begin!`/`resume!`, que desfazem o preparo
    local e relançam (origem volta a `active`, pedido vai a `aborted`; 409 no contrato do serviço; o park interno
    de `queued` já foi desfeito pela T0.7b antes de levantar).
  - `begin!`: `take_origin!` + `prepare_conversation!` + `settle_begin!` sob o mesmo lock/transação; `uncertain`
    aborta o preparo local e relança. Retorna `PROCEED` ou `WAIT`.
  - `resume!`: reavalia depois de um `WAIT` sob o lock (recarrega o pedido aberto por `source_conversation_id`;
    `queued` novo vira `parked` via `recheck_conversation!`): sem pendência o pedido volta a `requested` e retorna
    `PROCEED`; com `dispatching` mantém `awaiting_dispatch` e retorna `WAIT`; com `uncertain` aborta e relança.
    Sem pedido aberto, origem fora de `transferring` ou inbox não marcada ⇒ `PROCEED` (nada a reter).
  - `commit_local!(target_case_version:, summary:)`: revalida a barreira antes de gravar (`recheck_conversation!`).
    Com `dispatching` em voo, volta o pedido a `awaiting_dispatch` e devolve `WAIT` sem commitar; com `uncertain`,
    aborta o preparo local (origem volta a `active`, pedido a `aborted`) e relança. Sem pendência, resolve a origem
    por `update_column` (sem callbacks, como na T0.7a), grava origem `transferred_out`, cria o destino
    `pending_activation` com a nota de resumo e o pedido vai a `committed_local` — tudo atômico. Depois do commit,
    a origem nunca reabre (só `find_by` em `transferring` prossegue) e o destino continua `pending_activation`
    até `activate!` com a versão confirmada. Idempotente: commit repetido devolve a conversa destino criada.
  - `abort!`: só antes do commit (`find_by!` em `transferring`): origem volta a `active`, pedido aberto vai a
    `aborted` — cobre também desistência de um preparo retido em `awaiting_dispatch`. Depois do commit a busca
    falha e nada muda.
  - `activate!`/`mark_stuck!`: inalterados (T0.7a). `call`: se `begin!` pedir espera, devolve `WAIT` sem commitar;
    chame `resume!` até `PROCEED` e só então `commit_local!`.
  - Resumo atômico e locks do T0.3/T0.7a mantidos: todo o preparo/commit roda sob `locked` (transação +
    `pg_advisory_xact_lock` de (inbox, contato)); resumo e destino nascem no mesmo commit.
  - `OutboundDispatch` (T0.7b) usado como está, sem reescrita.

## 2. Mapeamento aos critérios de aceite (código, sem prova)

- AC1 (nenhum interno chamado por `begin!`/`resume!`/`commit_local!` fica indefinido): `take_origin!`,
  `prepare_conversation!`, `settle_begin!` definidos; `recheck_conversation!`, `load_open_record!`,
  `retry_open_record!`, `reuse_open_record!`, `abort_open_record!`, `transfer_scoped?` dão suporte. **Não validado.**
- AC2 (`dispatching` aguarda; `uncertain` bloqueia e permite origem `active` antes do commit; `commit_local!`
  nunca ignora pendente/incerto): `begin!`⇒`awaiting_dispatch`/`WAIT`; `resume!` reavalia; `commit_local!`
  revalida e só commita sem pendência; `uncertain` aborta e relança nos três pontos. **Não validado.**
- AC3 (origem nunca reabre após commit; destino segue `pending_activation` até confirmação de versão):
  commit grava `transferred_out` + `committed_local` atomicamente; pós-commit só `activate!` (versão) ou
  `mark_stuck!` tocam o destino; `abort!`/`abort_open_record!` só agem em `transferring`/pedido aberto.
  **Não validado.**
- AC4 (só arquivos próprios mudam; relatório separa implementação de validação): alterados só
  `local_transaction.rb`, esta evidência e append no changelog do dia. Este relatório declara explicitamente
  que nada foi executado. **Checar em `git status --short` (seção 4).**

## 3. Limites e decisões que o revisor precisa conhecer

- **NÃO VALIDADO:** sintaxe Ruby, RuboCop, specs (novos ou regressão), e qualquer execução pelo runner ficam para
  tarefa posterior. `git diff --check` e `git status --short` são as únicas checagens desta tarefa.
- `prepare_transfer!` roda em `requires_new: true`; o `ConflictError` em `begin!`/`resume!`/`commit_local!` é
  capturado fora da subtransação, então o `abort_open_record!` (origem `active`, pedido `aborted`) persiste.
- `resume!`/`commit_local!` recarregam o pedido por `source_conversation_id` (`@scope.conversation_id`), não por
  `@record.id`: a instância pode ser nova (outro `LocalTransaction` para o mesmo par) e `@record` pode ser `nil`.
- `activate!`/`mark_stuck!` ainda usam `@record.id` (inalterados da T0.7a); chamadas com outra instância após
  `commit_local!` seguem o limite pré-existente, fora do escopo desta tarefa.
- Inbox não marcada não ganha comportamento de spike (sem `prepare_transfer!`, sem `awaiting_dispatch`).
- Cancelamento de agendadas/recorrentes da origem continua fora deste turno (limite herdado da T0.7a).
- Reenvio manual (retry/reações) em inbox marcada continua pendente (limite herdado da T0.7b).

## 4. Arquivos e validação estática

- Alterados: `app/services/connecta/transfer/local_transaction.rb` (implementação T0.7c), este arquivo,
  append em `.context/changelog/CHANGELOG_2026_10_23.md` (seção T0.7c).
- Leitura: `outbound_dispatch.rb` (contrato estável, sem alteração), `transfer_record.rb`,
  `outbound_dispatch_record.rb`, `spec/connecta/support/g0_transfer_schema.rb` (colunas do pedido), plano
  §§6.5 e 7 (`2026-10-22-atendimento-dois-numeros-baileys.md:321-444`), evidências 10/16/17.
- NÃO tocados: `scope/**`, installer, runner, schema, core, `.env`, specs, `PROJECT_STATE.md`, plano.
- Validação: `git diff --check` e `git status --short` (checagens estáticas apenas). **Specs, RuboCop e build
  NÃO executados** por instrução do humano; execução é tarefa posterior da fase.

## 5. Specs escritos, NAO executados + limpeza concluida (append T0.7c-2, 2026-10-24)

- `spec/connecta/transfer_integration_spec.rb`: 11 exemplos escritos conforme o log do turno
  anterior (T0.7c-2), contra a API real de `LocalTransaction` com transporte stubado
  (`SendOnWhatsappService` dobrado, `SendReplyJob` real), sem sleep/rede/threads; fixture de escopo
  transacional (rollback limpa tudo, sem `after` manual). **NAO EXECUTADA** por ordem do humano
  ("implementar tudo, completo ... depois vamos testando"): nenhum run, log de spec ou validacao
  funcional neste turno nem nos anteriores para estes 11 exemplos.
- `spec/connecta/transfer_cutover_spec.rb`: ensure/rollback/join concluidos na retomada de codigo
  (turno COMPLETED so codigo, 2026-10-24): erros de thread propagados via `value`, `join` limitado
  (10 s) + `kill` + `release_connection` nos trechos concorrentes; `after` limpa por IDs proprios
  (transfers/dispatches SEM `account_id`: so linhas das conversas da inbox do exemplo, ANTES de
  apagar as conversas; tabelas com `account_id` por conta); contagem de sobras com expectativa de
  zero; residuos antigos de outras execucoes preservados por desenho. `ruby -c` passou no turno de
  codigo. **Spec NAO EXECUTADA** (validacao funcional pendente, tarefa posterior).
- Detalhe, hipotese de concorrencia-sem-fila, achado `transfers`/`dispatches` sem `account_id`,
  leitura dos logs antigos de 0 exemplos (nao provam estabilidade) e preservacao dos residuos:
  ver `.context/evidence/g0/21-instabilidade.md`. Nada aqui alega spec executada ou instabilidade
  corrigida com prova: nenhuma nova execucao ocorreu.
