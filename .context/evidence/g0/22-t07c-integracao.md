# Evidência 22 · T0.7c integração transferência ↔ despacho em voo (spike G0)

Data: 2026-10-24. Worktree: `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`. Local, dados sintéticos, execução só pelo runner `scripts/connecta/g0_test_env.sh --spec --apply` sob `spec.lock`. Sem rede, sem teardown, sem migração, sem escrita direta. O código T0.7c (`local_transaction.rb`) e a spec T0.7c-2 (`transfer_integration_spec.rb`) vieram de turnos anteriores; este turno verificou conformidade, fez 2 ajustes pequenos (`resume!` volta a `requested`; refator de complexidade) e validou o viável.

**Estado: PARCIALMENTE VALIDADO (código + estática verdes; specs bloqueados por divergência de migração de outro front).** AC1–AC2 provados por leitura + estática; AC3 (spec nova) escrita e com sintaxe OK, mas NÃO executada; AC4 parcial (RuboCop verde nos 2 `.rb` tocados, `git diff --check` limpo, trio de regressão NÃO executado); AC5 cumprido aqui (evidência + changelog + logs do abort).

## 1. O que foi construído (turnos anteriores, verificado neste)

- `app/services/connecta/transfer/local_transaction.rb`: completa a T0.7c sobre `begin!`/`commit_local!` da T0.7a.
  - `take_origin!`: origem `active → transferring` sob o lock de (inbox, contato) do T0.3, atomizado com o pedido `TransferRecord` em `requested`. Idempotente: `begin!` repetido reutiliza o pedido aberto (`RecordNotUnique` recai em `retry_open_record!`); origem já em `transferring` reutiliza via `reuse_open_record!`.
  - `prepare_conversation!(origin)` / `recheck_conversation!(origin)`: inbox marcada ⇒ `OutboundDispatch.prepare_transfer!` (contrato estável da T0.7b, sem reescrita: parka `queued`, `wait=true` com `dispatching`, `ConflictError` com `uncertain`); inbox não marcada ⇒ sem barreira (`Result(parked: 0, wait: false)`).
  - `settle_begin!(result)`: `wait=true` ⇒ pedido vai a `awaiting_dispatch`, retorno `WAIT`; sem pendência ⇒ `PROCEED`. `ConflictError` sobe para `begin!`/`resume!`/`commit_local!`, que desfazem o preparo local (`abort_open_record!`: origem volta a `active`, pedido a `aborted`) e relançam (409 no contrato do serviço; o park interno de `queued` já foi desfeito pela T0.7b antes de levantar).
  - `begin!`: `take_origin!` + `prepare_conversation!` + `settle_begin!` sob o mesmo lock/transação. Retorna `PROCEED` ou `WAIT`; `uncertain` aborta o preparo local e relança.
  - `resume!`: reavalia depois de um `WAIT` sob o lock (recarrega o pedido por `source_conversation_id`; `queued` novo vira `parked`): sem pendência o pedido **volta a `requested`** (transição `awaiting_dispatch → requested` do plano §7, ajuste deste turno) e retorna `PROCEED`; com `dispatching` mantém `awaiting_dispatch` e retorna `WAIT`; com `uncertain` aborta e relança. Sem pedido aberto, origem fora de `transferring` ou inbox não marcada ⇒ `PROCEED`. Helpers `resumable?`/`recheck_and_settle!` extraídos neste turno para RuboCop.
  - `commit_local!(target_case_version:, summary:)`: revalida a barreira antes de gravar. Com `dispatching`, volta o pedido a `awaiting_dispatch` e devolve `WAIT` sem commitar; com `uncertain`, aborta o preparo local e relança. Sem pendência, resolve a origem por `update_column` (sem callbacks, como na T0.7a), grava `transferred_out`, cria o destino `pending_activation` com a nota de resumo e o pedido vai a `committed_local` — tudo atômico. Depois do commit, a origem nunca reabre; idempotente (commit repetido devolve o destino criado).
  - `abort!`: só antes do commit (`find_by!` em `transferring`): origem volta a `active`, pedido aberto vai a `aborted` — cobre desistência de `awaiting_dispatch`. `activate!`/`mark_stuck!`: inalterados (T0.7a). `call`: se `begin!` pedir espera, devolve `WAIT` sem commitar.
  - `OutboundDispatch` (T0.7b) usado como está, sem reescrita; `transfer_scoped?` isenta inbox não marcada.
- `spec/connecta/transfer_integration_spec.rb` (T0.7c-2, turno anterior): 11 exemplos contra a API real com transporte stubado, fixture transacional, sem sleep/rede/threads. **NÃO EXECUTADA** (bloqueio abaixo).

## 2. Como cada AC é provado (ou por que está pendente)

| AC | Prova |
|---|---|
| AC1 — `begin!` parka `queued`, espera em `dispatching` (`awaiting_dispatch`), conflita em `uncertain` (origem volta a `active`) | Leitura: `take_origin!` + `prepare_conversation!` + `settle_begin!` (`local_transaction.rb:48-61,185-227`); `prepare_transfer!` parka-antes-de-ler (`outbound_dispatch.rb:51-63`). Estática: `ruby -c` OK nos 2 `.rb`, RuboCop 0 ofensas. Execução: **pendente** (bloqueio abaixo); spec T0.7c-2 cobre (`transfer_integration_spec.rb:44-54` queued, `:56-67` dispatching→accepted, `:87-95` uncertain no begin, `:97-106` uncertain no commit). |
| AC2 — `commit_local!` recusa com `dispatching`/`uncertain` | Leitura: `commit_local!` revalida via `recheck_conversation!` antes de gravar (`local_transaction.rb:104-126`): `barrier.wait` ⇒ `awaiting_dispatch` + `WAIT` sem commitar; `ConflictError` ⇒ `abort_open_record!` + relança. Execução: **pendente**; spec cobre (`transfer_integration_spec.rb:97-106`). |
| AC3 — (movido para T0.7c-2 pelo briefing) | Spec escrita, sintaxe OK, **não executada**. |
| AC4 — regressão + RuboCop | RuboCop nos 2 `.rb` tocados: **0 ofensas, exit 0**. Trio de regressão **não executado** (bloqueio abaixo). `git diff --check` limpo; `git status` só `??` (nada rastreado alterado). |
| AC5 — evidência 22, changelog, sem mudança rastreada | Este arquivo + append no changelog de hoje + logs em `22-logs/`. |

## 3. Runs reais (em `22-logs/`)

| Run | Conteúdo | Resultado | Exit | Situação |
|---|---|---|---|---|
| `trio-run-1.log` | trio pelo runner com lock (`transfer_activation` + `transfer_cutover` + `outbound_dispatch`) | abort na pré-condição `db_matches_schema` (nenhum exemplo executado) | 1 | bloqueado (ver 4) |
| `rubocop-t07c.log` (este turno) | `local_transaction.rb` + `outbound_dispatch.rb` (`env -i` + `BUNDLE_*` do launcher) | **0 ofensas** (após refator `resumable?`/`recheck_and_settle!`; antes: 2 de complexidade em `resume!`) | 0 | válido |
| `ruby -c` (este turno) | `local_transaction.rb`, `outbound_dispatch.rb`, `transfer_integration_spec.rb` | Syntax OK ×3 | 0 | válido |

## 4. Bloqueio das specs (evidência, sem correção possível neste turno)

- O runner aborta em `db_matches_schema`: o banco tem sha1/repo iguais (`d72f5973…`) e as mesmas tabelas, mas `db/migrate/` lista a versão `20261024000000` (`db/migrate/20261024000000_create_connecta_human_number_tables.rb`, untracked de outro front) ausente em `schema_migrations`. Comparação por `comm` confirma: só essa versão no repo, nenhuma só no banco.
- Correções possíveis (rodar `db:migrate`, recarregar schema, mover/renomear arquivo alheio) são **proibidas**: sem migração, sem escrita direta, sem tocar arquivo de outro front. Reportado como BLOCKED parcial: estática verde, execução pendente.
- O lock `spec.lock` estava livre (`flock -n` OK); o abort foi do runner, não de contenção.

## 5. Limites e decisões que o revisor deve conhecer

- **`retain_uncertain`/`HELD` não são do briefing:** `app/services/connecta/runtime/transfer_transaction.rb` (untracked, outro front) chama `LocalTransaction` com `retain_uncertain: true` e trata `HELD`. O comportamento do briefing (G0 puro: `uncertain` ⇒ origem `active` + `aborted`) é o default (`retain_uncertain: false`) e é o que a spec T0.7c-2 cobre. Caminho `HELD` sem exemplo executado.
- `resume!` sem pedido aberto / origem fora de `transferring` / inbox não marcada ⇒ `PROCEED` (nada a reter). Idempotência de `begin!` repetido reutiliza o pedido da mesma origem.
- `activate!`/`mark_stuck!` ainda usam `@record.id` (limite pré-existente da T0.7a); chamadas com outra instância após `commit_local!` seguem fora de escopo.
- Cancelamento de agendadas/recorrentes da origem e reenvio manual (retry/reações) seguem pendentes (limites herdados T0.7a/T0.7b). Status visível de `parked` é UI (Fase 5).

## 6. Arquivos e validação estática

- Alterados neste turno: `app/services/connecta/transfer/local_transaction.rb` (transição `awaiting_dispatch → requested` em `resume!` + refator de complexidade), este arquivo, append no changelog de hoje.
- Herdados (turnos anteriores, verificados): `app/services/connecta/transfer/outbound_dispatch.rb` (inalterado, contrato estável), `spec/connecta/transfer_integration_spec.rb` (sintaxe OK, não executada).
- Leitura: plano §§6.5–7 (`2026-10-22-atendimento-dois-numeros-baileys.md:321-444`), `transfer_record.rb`, `outbound_dispatch_record.rb`, `g0_transfer_schema.rb`, evidências 10/16/17/18.
- NÃO tocados: `scope/**`, `support/*`, `scripts/connecta/*`, core, `.env`, outros specs, `PROJECT_STATE.md`, plano. `outbound_dispatch_spec.rb`, `transfer_activation_spec.rb`, `transfer_cutover_spec.rb` **não editados**.
- Validação: `ruby -c` ×3 OK; RuboCop 2 arquivos 0 ofensas; `git status --short` só `??`; `git diff --check` limpo. Specs **não executados** (bloqueio §4).
