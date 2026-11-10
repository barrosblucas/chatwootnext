# Changelog 2026-11-10

## Fase 1 vinculo simplificado: correcoes de seguranca do revisor (privilegiados, lapide de trinca, invalid_password)

- Achados (revisor rejeitou o fork; humano aprovou "corrigir junto com o que o revisor apontar"):
  1. Sem guarda de privilegiado: `set_password!`/`deactivate!`/`provision!` so barravam `administrator` do vinculo da conta; SuperAdmin (STI `users.type`) ou administrator em OUTRA conta passava (senha/tokens sao globais no User).
  2. Bypass de lapide legada: `grant.revoke` com `grant_id` lapidava so o `grant_id`; um `grant.upsert` legado (sem `grant_id`, WP `c47dd1c`) da mesma trinca recriava o acesso.
  3. `RecordInvalid` do Devise no `set_password!` caia em 422 `provision_rejected`; o documentado e 422 `{error:"invalid_password", reason}`.
- Codigo (branch `feat/vinculo-simplificado-fase1`):
  - `app/services/connecta/provisioning/agent_provisioner.rb`: novo `privileged?` (`type == 'SuperAdmin'` OU `account_users` com `administrator` em qualquer conta); `provision!`/`set_password!`/`deactivate!` levantam `NotAgent` (409 `not_agent`) sem criar/alterar nada; `set_password!` converte `RecordInvalid` em `InvalidPassword` (422 `invalid_password`). Mudanca de contrato: `provision` agora pode retornar 409 `not_agent` (WP trata como erro `chatwoot_role_not_agent`).
  - `db/migrate/20261109000000_add_grant_tombstones_to_connecta_acl.rb` (mesmo arquivo novo, ainda nao aplicado em producao — `origin/main` nao o contem; max prod `20261024000001`): `connecta_revoked_grants` ganha `user_id`/`org_unit_id`/`permission` + indice da trinca; `down` atualizado. `db/schema.rb` e `app/models/connecta/revoked_grant.rb` (anotacao) espelham.
  - `app/services/connecta/runtime/acl_sync_service.rb`: `revoke_grant_by_id!` com trinca completa tambem lapida a trinca; `upsert_grant!` sem `grant_id` de trinca lapidada e ignorado; com `grant_id` novo aplica e limpa so a trinca (lápides por `grant_id` antigo seguem valendo — extraido em `legacy_tombstoned_grant?` para nao estourar `Metrics/CyclomaticComplexity`). Revoke so com `grant_id` (sem trinca) nao lapida trinca: legado ainda recria (compat WP `c47dd1c`).
- Specs (escritas antes da correcao, falham sem ela):
  - `spec/requests/connecta/users_provisioning_spec.rb`: agente-em-A+admin-em-B e SuperAdmin -> password/deactivate/provision 409 sem nada mudar; teste antigo "keeps the administrator role" virou 409 `not_agent`; `RecordInvalid` do Devise (`NoSpecial1234`: 14 chars sem especial) -> 422 `invalid_password`.
  - `spec/connecta/runtime_acl_sync_grants_spec.rb`: upsert legado apos lapide nao recria; re-concessao com `grant_id` novo restaura e limpa a lapide; revoke so com `grant_id` nao veta o legado.
- Validacao: `ruby -c` OK nos 6 RB via container `chatwootnext:local` (montagem `:ro`); `bundle exec rspec`/`rubocop` indisponiveis localmente (sem Ruby; rubocop fora do bundle da imagem) — validado pelo CI (`run_foss_spec.yml` workflow_dispatch no branch). Baseline lint-backend (74 ofensas pre-existentes) e security-scan (CVEs de Rails) seguem aceitos; nenhum arquivo tocado adiciona ofensa nova (complexidade/linhas conferidas contra `.rubocop.yml`: LineLength 150, MethodLength 19, CyclomaticComplexity padrao 7).
- Historico CI (`run_foss_spec.yml`, workflow_dispatch no branch):
  - run 1 (`c9964cc8`, run 42743035331): backend-tests (0) success — 114 exemplos, 0 falhas (specs novos inclusos); lint-backend failure com 75 ofensas = 74 pre-existentes + 1 nova em arquivo tocado (`Rails/WhereExists` em `acl_sync_service.rb:131`, meu `where(...).exists?`); security-scan failure (baseline: CVEs de Rails/brakeman, sem gem nova).
  - correcao (`14e86c4f`): `triple_tombstoned?` usa `exists?(...)` direto.
  - run 2 (`14e86c4f`, run 42743519530): backend-tests (0) success — 114 exemplos, 0 falhas; lint-backend failure com 74 ofensas = baseline, ZERO nos arquivos tocados; security-scan failure (mesmo baseline). AC1–AC4 atendidos.


## Fixed
- Correção 01 (transferência some da contagem / destino não aparece sem reload): após `scope.revoked` o front refaz `fetch_conversation_stats`; `TransferAction` usa o id capturado antes do POST (race-safe), emite stats e, no caminho human-number (202 sem `display_id`), volta para a lista da aba atual em vez de permanecer na rota da origem (404).
- Ativação da transferência reanuncia `conversation.created` pelo dispatcher padrão depois do commit (só na transição; idempotente não reanuncia): o gate do socket entrega só a quem lê o destino (READ_STATES + grant ancestral).
- `CacheRevocation.scope!`: direção do grant corrigida (grant ancestral libera, gate.rb `granted_sector?` — antes incluía descendente e excluía ancestral/nominal raiz) + admins nativos same-account passam a receber `scope.revoked`.

## Tests
- `actionCable.spec.js`: `scope.revoked` → commit + `bumpEpoch` + stats fetch; ignora conta alheia.
- `TransferAction.spec.js`: resposta human-number navega para a lista da aba (inbox) com o id capturado; seleção zerada mid-flight continua resolvendo/navegando; emite `fetch_conversation_stats`.
- `TransferActionSummary.spec.js`: atualizado para a navegação à lista no 202 sem `display_id` (+ mocks `useRoute`/`conversationListPageURL`/`dispatch`).
- Novo `spec/connecta/transfer_activation_broadcast_spec.rb`: announce gated no `activate!` (leitor do destino recebe, origem/sem grant não), sem reanúncio idempotente, e destinatários do `scope.revoked`.

## Validacao
- Local: `pnpm vitest run` nos 3 specs de front tocados — 53 passed; eslint direto nos 5 arquivos tocados — 0 errors (2 warnings pré-existentes).
- Ruby indisponível neste ambiente (`ruby: command not found`); RSpec real via `run_foss_spec.yml` no branch (ver CI abaixo).

## CI (run_foss_spec.yml no branch fix/transfer-contador-20261110)
- Run 42837578237 (head `2ce62fc7`): plan success; lint-frontend success; frontend-tests success; backend-tests (0) success (spec novo, 3 exemplos); lint-backend failure = baseline 74 (0 novos; 3 Metrics em `adopt_callback_scope!` pré-existentes); security-scan failure = baseline (Brakeman 41, nenhum nos arquivos tocados; bundle-audit só advisories de deps).
- Runs anteriores no mesmo branch: 42834228477 (3 exemplos do spec novo falhavam — namespace `Connecta::UserGrant` vs `Scope::` + `have_enqueued_job` no `ActionCableBroadcastJob`) e 42835491084 (2 falhavam — mesmos ajustes); ambos superados em `2ce62fc7`. Iterações de fix: 2 (dentro do limite).
