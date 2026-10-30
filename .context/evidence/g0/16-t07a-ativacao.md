# Evidência 16 · T0.7a barreira de ativação e despacho em voo (spike G0)

Data: 2026-10-23. Worktree: `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`. Local, dados sintéticos, banco `conecta_baileys_g0_test`, execução só pelo runner `scripts/connecta/g0_test_env.sh --spec --apply` sob `spec.lock`. Sem rede (perfis e recibos stubados no spec); sem teardown, sem migração, sem escrita direta.

**Estado: FECHADO (T0.7a). AC1 a AC5 verdes.** Par `transfer_activation_spec.rb` + `transfer_cutover_spec.rb`: **19 exemplos, 0 falhas, exit 0, 3 vezes em sequência** (runs 11, 12, 13). RuboCop nos 2 arquivos: 0 ofensas (`rubocop-t07a-run-3.log`). Nenhum arquivo rastreado alterado (`git status --short` só mostra `??`, `git diff --check` vazio).

## 1. O que foi construído

- `app/services/connecta/transfer/local_transaction.rb`: `Connecta::Transfer::LocalTransaction`.
  - `self.lock!`: `pg_advisory_xact_lock(hashtextextended('connecta:transfer:<inbox>:<contato>'))` — o mesmo lock de (inbox, contato) que a mensagem entrante toma (T0.3), na mesma sessão/transação.
  - `call(summary:)`: `begin!` + `commit_local!` numa transação só; falha em qualquer etapa desfaz tudo.
  - `begin!`: origem `active → transferring`; cria `TransferRecord` em `requested`.
  - `commit_local!(target_case_version:, summary:)`: origem `transferring → transferred_out`; resolve a conversa de origem por `update_column` (sem callbacks, sem mensagem de atividade na origem); abre o destino (`Conversation` + escopo `pending_activation` + nota privada de resumo); registro vai a `committed_local` com `destination_conversation_id` e `target_case_version`.
  - `abort!`: só antes do commit (`find_by!` em `transferring`): origem volta a `active`, registro vai a `aborted`. Depois do commit a busca falha (`RecordNotFound`) e nada muda.
  - `activate!(case_version:)`: só com a versão confirmada igual à alvo do commit (`find_by!` em `committed_local` + `VersionMismatch` senão, sem mudar nada); destino `pending_activation → active` com `case_version`, registro vai a `committed`.
  - `mark_stuck!`: divergência irrecuperável depois do commit: destino e registro vão a `activation_stuck` (destino só para admin); a origem nunca volta.
- `app/services/connecta/transfer/transfer_record.rb` (leitura de referência, fora de escopo): `STATES` inclui `requested`, `committed_local`, `committed`, `aborted`, `activation_stuck` (além de `awaiting_dispatch`, `prepared`, `rejected`, `unknown` da T0.7b).
- `spec/connecta/transfer_activation_spec.rb`: 10 exemplos. Fixture de escopo real + `IncomingHook` real (Baileys sem rede) + Gate/policies/hooks reais. Transições de `TransferRecord`: `requested` (begin) → `committed_local` (commit) → `committed` (activate) / `aborted` (abort pré-commit) / `activation_stuck` (mark_stuck).

## 2. Como cada AC é provado (linhas do spec)

| AC | Exemplo (spec:linha) | Prova |
|---|---|---|
| AC1 — destino invisível em `pending_activation`; admin auditado | `transfer_activation_spec.rb:84` (agente B: 404 + fora da lista) | `GET conversa destino` → 404; lista do agente B contém só `conv_b` |
| AC1 — mensagem do cidadão entra no destino | `transfer_activation_spec.rb:76` | `msg-pending` cai em `destination.id`; origem segue `transferred_out`, destino segue `pending_activation` |
| AC1 — leitura admin auditada | `transfer_activation_spec.rb:94` | admin nominal lê com 200; 1 linha `AccessAudit(allow, detail)` |
| AC2 — só a versão confirmada ativa | `transfer_activation_spec.rb:104` (versão errada recusada, nada muda) + `:112` (versão certa ativa, agente B vê com resumo) | `VersionMismatch`; destino segue `pending_activation/case_version 0`, registro segue `committed_local` |
| AC3 — origem nunca reabre pós-commit; begin+abort volta a active | `transfer_activation_spec.rb:132` (abort pós-commit levanta `RecordNotFound`, origem segue `resolved/transferred_out`) + `:141` (agente A não cria mensagem, 404) + `:149` (toggle para open negado: 404 agente A, 403 admin nominal) + `:163` (begin+abort: `transferring → active`, registro `aborted`) | origem travada após o commit; abort só pré-commit |
| AC4 — par verde 3/3 + RuboCop | runs 11–13 (ver 3) | 19/0, exit 0, 3×; RuboCop 2 arquivos, 0 ofensas |

## 3. Runs reais (em `16-logs/`)

| Run | Conteúdo | Resultado | Exit | Situação |
|---|---|---|---|---|
| run-5 (histórico) | par activation + cutover | 19 ex., 6 falhas (`activation:84,94,122,141,149` + `cutover:182`) | 1 | superado; falha de flake geral, investigada por outro Coder (`ps-sampler-run-7.log`) |
| run-6 | par | 19 ex., 0 falhas | 0 | válido (anterior) |
| run-7 | par | 19 ex., 0 falhas | 0 | válido (anterior) |
| activation-alone-run-1 | só activation | 10 ex., 0 falhas | 0 | válido |
| cutover-alone-run-1 | só cutover | 9 ex., 0 falhas | 0 | válido |
| run-8 | par (flake-investigação) | 19 ex., 0 falhas | 0 | citado, não meu |
| run-9 | par (flake-investigação) | 19 ex., 0 falhas | 0 | citado, não meu |
| run-10 | par | 19 ex., 0 falhas | 0 | válido (anterior) |
| **run-11** | **par (este turno)** | **19 ex., 0 falhas** | **0** | **válido** |
| **run-12** | **par (este turno)** | **19 ex., 0 falhas** | **0** | **válido** |
| **run-13** | **par (este turno)** | **19 ex., 0 falhas** | **0** | **válido** |

RuboCop: `rubocop-t07a-run-1.log` (14 ofensas, versão anterior: `Metrics/*` no `commit_local!`, `Style/IfUnlessModifier`, `Layout/LineLength`, `RSpec/*` na spec), `rubocop-t07a-run-2.log` (3 arquivos, 0 ofensas, run anterior), **`rubocop-t07a-run-3.log` (2 arquivos, 0 ofensas, exit 0 — este turno)**. Diferença 3 vs 2: o run 2 incluiu um terceiro arquivo (não identificado neste turno); a validação desta tarefa cobre os 2 arquivos in-scope.

Sobre o run 5: 5 falhas de activation mostram o Gate aberto (200 em vez de 404, sem auditoria, escrita na origem permitida) + 1 falha de cutover (`transfer_cutover_spec.rb:182`, `committed_while_in_flight` não nulo). Outro Coder investiga o flake geral; nenhum arquivo compartilhado foi alterado neste turno.

## 4. Limites e decisões que o revisor deve conhecer

- **Agendamento/cancelamento da origem:** sem menção no código (`schedul|recurr|cancel` → 0 ocorrências em `transfer/`, activation e cutover). A origem é resolvida no commit local (`update_column :resolved`) e o Gate nega leitura/escrita/toggle depois disso (spec `:141`, `:149`), mas cancelamento de agendados/recorrentes não é tratado aqui — pendente ou inexistente, decisão fora deste turno.
- **`prepare_transfer!` (T0.7b) ainda não ligado ao `begin!`:** `outbound_dispatch.rb:51` existe, mas nenhuma chamada em `local_transaction.rb` nem na activation spec (`prepare_transfer` → 0 ocorrências). Wiring é a tarefa T0.7c, fora de escopo.
- **Outros estados do registro** (`awaiting_dispatch`, `prepared`, `rejected`, `unknown`) são da T0.7b, não usados por este spec.
- **Origem da garantia de corrida:** herdada do T0.3 (lock de (inbox, contato) na mesma sessão); este spec não repete a prova de corrida.

## 5. Arquivos e alterações no repo

- Validados (sem alteração de código neste turno): `app/services/connecta/transfer/local_transaction.rb`, `spec/connecta/transfer_activation_spec.rb`.
- Novos: este arquivo e os logs `16-logs/activation-cutover-run-11.log`, `run-12.log`, `run-13.log`, `16-logs/rubocop-t07a-run-3.log`.
- Atualizado: `.context/changelog/CHANGELOG_2026_10_23.md` (entrada T0.7a, por append).
- Não tocados: `transfer/{installer,outbound_dispatch,send_reply_hook,incoming_hook,transfer_record,outbound_dispatch_record}.rb`, `transfer_cutover_spec.rb`, `outbound_dispatch_spec.rb`, `scope/**`, `support/*`, `scripts/connecta/*`, core, `.context/PROJECT_STATE.md`. Nenhum arquivo rastreado alterado.
