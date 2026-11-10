# Changelog 2026-11-10

## Specs stale do heartbeat/grace B5 (test-only; merged to main)

- Base: `5752fd8d` (fork main em 2026-11-10; worktree `/home/thanos/wt-chatwoot-specs-20261110`, branch `fix/specs-heartbeat-20261110`, commit `1e5ae978`).
- Causa: 2 failures PRE-EXISTENTES desde Phase-1 `2b45dc6c3` (também vermelhos em produção `6c32c0e2`, run 42744485954; verdes em `0e4bcf18`): specs stale, não bugs de produção. Nenhuma mudança em código de produção.
- Fix 1 — `spec/lib/connecta_common_product_tables_spec.rb:93-97`: o regex `/rescue.*false/m` varria `projection.rb` inteiro e passou a casar o `heartbeat_usable?` fail-closed (`rescue ArgumentError; false`, intencional). Asserção restringida à fonte de `self.marked?` (extrai `def self.marked?`...`end`; exige presente e sem `rescue.*false`). Intenção do spec preservada (sem fail-open em `marked?`).
- Fix 2 — `spec/connecta/attachment_download_scope_spec.rb:326`: `10.minutes.ago` caiu dentro da nova janela TTL 120 s + graça 900 s → 200, não 404. Trocado para `30.minutes.ago` (igual `scope_policy_query_spec.rb:184`); adicionados irmãos `5.minutes.ago` → 200 (janela de graça) e `with_modified_env CONNECTA_ACL_STALE_GRACE_SEC: '0'` + 10 min → 404 (padrão `scope_policy_query_spec.rb:218-225`).
- Hardening opcional (`transfer_scope_revoked_runtime_spec.rb:14`, `install!` em load) NÃO aplicado: siblings (`scope_policy_query_spec`, `attachment_download_scope_spec`) fazem o mesmo em load; mudar só este quebraria a consistência sem ganho — reportado ao orquestrador.
- CI (dispatch `full=true` no branch): run 42862344792 (head `1e5ae978`) — plan/lint-frontend/frontend-tests success; backend-tests (0-7) TODOS success (shards 4 e 6, antes failing, agora verdes); lint-backend failure = baseline idêntico (74 ofensas, ZERO nos 2 arquivos tocados — verificado no log do job 129991525617; baseline run 42856000722 job 129969059203 também 74); security-scan failure = baseline idêntico (mesmo step `Run bundle-audit`; baseline job 129969058347 falha no mesmo step). Ruby/GH-CLI indisponíveis localmente; validação via API do GitHub com credential helper (token nunca impresso).
- MERGE EXECUTADO (fast-forward de `5752fd8d` para o tip do branch): a linha anterior ("main moveu para `c12ed527`") era uma checagem no repo errado (conectacidade, não chatwootnext) — a main do fork seguiu em `5752fd8d` (`ls-remote` == `origin/main`, ancestral do branch). Imagem `ee-src-5752fd8d` NÃO reconstruída (mudança só de teste/docs).

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

## Rebase sobre main 6c32c0e2 (correcao 01 continua; base anterior 0e4bcf18 estava defasada)
- Rebase dos 4 commits do fix para `6c32c0e2` (Phase 1: provisioning, grant tombstones, heartbeat grace); unico conflito no changelog do dia (uniao das secoes, sem perda).
- `CacheRevocation.scope!` revalidado contra a Phase 1: gate (`granted_sector?`, agora sob `usable?`) e tabelas inalterados no que importa — continua lendo `Scope::UserGrant`/`Scope::OrgUnit` (g0, mesma fonte do gate), prefixo ancestral, + admins nativos; grants revogados (tombstones destroem a linha) saem sozinhos dos destinatarios.
## Rebase sobre main 6c32c0e2 (correção 01 continua; base anterior 0e4bcf18 estava defasada)
- Rebase dos 4 commits do fix para `6c32c0e2` (Phase 1: provisioning, grant tombstones, heartbeat grace); unico conflito no changelog do dia (uniao das secoes, sem perda).
- `CacheRevocation.scope!` revalidado contra a Phase 1: gate (`granted_sector?`, agora sob `usable?`) e tabelas inalterados no que importa — continua lendo `Scope::UserGrant`/`Scope::OrgUnit` (g0, mesma fonte do gate), prefixo ancestral, + admins nativos; grants revogados (tombstones destroem a linha) saem sozinhos dos destinatarios.
- CI pos-rebase, run 42839986935 (head `b0c76a07`): plan success; lint-frontend success; frontend-tests success; backend-tests (0) success; lint-backend failure = baseline 74 (0 novos; mesmos 3 Metrics pre-existentes em `adopt_callback_scope!`); security-scan failure = baseline (Brakeman 41, 0 nos arquivos tocados).

## Revisor: revogacao agnostica a tabela + announce nao-fatal (achado critico procede)
- Achado: `cache_revocation.rb` hardcodava `connecta_g0_org_units`; em producao o G0Adapter remapeia Scope:: para `connecta_org_units` -> `StatementInvalid` em todo commit (transfer_transaction.rb:159), sem rescue, commit pela metade. CI em modo G0 nao pegava.
- Prova failing-first, run 42844564343 (spec-only `738e014a`): `PG::UndefinedTable: missing FROM-clause entry for table "connecta_g0_org_units"` em `cache_revocation.rb:12` via `commit_local_destination!` — o commit nao retornava `pending_activation`.
- Fix: `quoted_table_name` + `.merge(Scope::OrgUnit.where(enabled: true))` + LIKE com coluna quotada do modelo; leitores por grant filtrados por epoca valida (`revoked_locally_at: nil`, espelho de projection `verified?`; nativo bypassa epoca como no gate); `announce_scope_revoked` com rescue+warn em `commit_local_destination!` (nunca aborta o commit).
- Novo `spec/connecta/transfer_scope_revoked_runtime_spec.rb` (modo runtime, `G0ProductTables.install!`): commit integral retorna `pending_activation` e anuncia a leitor da origem/ancestral/nativo, excluindo descendente/sem-grant/epoca-revogada.
- CI verde, run 42852767286 (head `f63922af`): plan/lint-frontend/frontend-tests/backend-tests success; lint-backend failure = baseline 74 com ZERO nos arquivos tocados (3 Metrics `adopt_callback_scope!`/`prepare_remote!`/`transfer_transaction` pre-existentes); security-scan = baseline (Brakeman 41, 0 nos tocados).


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
- Run 42837578237 (head `2ce62fc7`, base antiga `0e4bcf18`): plan success; lint-frontend success; frontend-tests success; backend-tests (0) success (spec novo, 3 exemplos); lint-backend failure = baseline 74 (0 novos; 3 Metrics em `adopt_callback_scope!` pré-existentes); security-scan failure = baseline (Brakeman 41, nenhum nos arquivos tocados; bundle-audit só advisories de deps).
- Runs anteriores no mesmo branch: 42834228477 (3 exemplos do spec novo falhavam — namespace `Connecta::UserGrant` vs `Scope::` + `have_enqueued_job` no `ActionCableBroadcastJob`) e 42835491084 (2 falhavam — mesmos ajustes); ambos superados em `2ce62fc7`. Iterações de fix: 2 (dentro do limite).

## Regra obrigatória de base na main remota (docs, 2026-11-10)

- `AGENTS.md` (raiz): nova seção "Base de trabalho (obrigatório)" — fetch + `ls-remote` == `rev-parse origin/main` antes de criar branch/worktree; base sempre o SHA da main remota; `merge-base --is-ancestor` do SHA em produção e da main remota antes de push/merge/deploy; nunca reutilizar worktree antiga sem refazer os passos.
- `.context/gotchas.md`: gotcha do incidente 2026-11-10 (branch de `0e4bcf18` local em vez de `6c32c0e2` remota).
- Verificação própria (passos 1–3 da regra): main remota `6c32c0e27d4265b36e776d7d24b1982f809af08a` == `origin/main` local (fetch ok); produção (`docker exec chatwootnext-rails-1 cat /app/.git_sha`) `6c32c0e27d4265b36e776d7d24b1982f809af08a` é ancestral de `HEAD` (`afdc9e89`); main remota é ancestral de `HEAD`. Branch `fix/transfer-contador-20261110`.

## Fase 2 · CSAT com protocolo + senha gerenciada (branch feat/fase2-csat)

- Base: main remota `57d4cf6365e90d8902971938e39db48f13c6ab5c` (fetch ok, ls-remote == origin/main); produção `5752fd8dd9477761af9b8b3c8d0671872970977e` ancestral de HEAD; worktree `/home/thanos/wt-chatwoot-fase2` criada desse SHA.

## Added
- `Connecta::Scope::CsatPolicy` (app/services/connecta/scope/csat_policy.rb): leitura única da projeção para o CSAT — inbox marcada, escopo com protocolo, `final_protocol_resolution?` (protocolo presente e estado != `transferred_out`; tolera a corrida com o hook de resolução, que roda depois do dispatcher do CSAT), `survey_message` (config `{{protocolo}}`/`{{protocol}}` ou padrão pt-BR), `feedback_disabled?`.
- `Connecta::Runtime::CsatPushJob` (app/jobs/connecta/runtime/csat_push_job.rb): `POST /attendance/v1/csat` via PlatformClient (HMAC fork→plataforma), retry 24x; payload `{account_id, conversation_id: display_id, case_protocol, rating, responded_at, csat_response_id}` — sem contato, sem comentário.
- `Connecta::Runtime::PasswordGuard` (app/services/connecta/runtime/password_guard.rb): `managed?` = AccountUser em CONNECTA_ACCOUNT_ID é `agent` e sem privilégio (não SuperAdmin, sem `administrator` em nenhuma conta).
- `spec/services/connecta_csat_fase2_spec.rb`: elegibilidade (final vs origem de transferência vs sem protocolo vs triagem), texto com protocolo, comentário descartado, payload do push (chaves exatas, sem PII), PasswordGuard (5 casos) e bloqueios de senha (forgot uniforme, reset 422, profile 422, admin liberado).

## Changed
- `CsatSurveyService`: inbox marcada só pesquisa a resolução final do protocolo; `build_csat_message` usa o texto do protocolo.
- `MessageTemplates::Template::CsatSurvey#message_content`: texto do protocolo (link anexado na renderização).
- `MessageContentPresenter`: conversa escopada com protocolo renderiza `✅ ... protocolo *{protocolo}* ... de 1 a 5: {link}`; demais casos byte-idênticos.
- `CsatSurveys::ResponseBuilder`: com `disable_feedback` descarta o comentário; resposta de conversa escopada com protocolo enfileira o push ao WP.
- `Public::Api::V1::CsatSurveyController#update`: descarta `feedback_message` quando `disable_feedback`; `show` expõe `disable_feedback`.
- `DeviseOverrides::PasswordsController#create`: gerenciado recebe o 200 uniforme sem disparar reset; `#update`: 422 com mensagem Facilita ao gerenciado.
- `Api::V1::ProfilesController#update`: troca de senha do gerenciado → 422 `{error: password_managed_by_facilita, message}`; demais fluxos intactos; HMAC `set_password` intocado.
- `survey/views/Response.vue`: `disable_feedback` esconde o formulário de comentário e envia só a nota; escala 1–5 inalterada (+3 testes em `Response.spec.js`).
- Frontend de senha: sem mudança — `ChangePassword.vue` e o fluxo "esqueci a senha" já exibem `message` do backend via `parseAPIErrorResponse`/`showAlertMessage`.

## Deploy (documentação — NÃO aplicar; outro Coder/operador no deploy)
- Habilitar CSAT na inbox 9 (rails runner, uma vez):
```ruby
inbox = Inbox.find(9)
inbox.update!(
  csat_survey_enabled: true,
  csat_config: inbox.csat_config.merge(
    'display_type' => 'star',
    'message' => '✅ Seu atendimento do protocolo {{protocolo}} foi finalizado.\nAvalie o atendimento de 1 a 5:',
    'disable_feedback' => true
  )
)
```

## Tests
- Ruby indisponível neste ambiente; sintaxe validada via `ruby -c` no container rails (11 arquivos, OK); linhas ≤150; `node --check` no script do Response.vue OK.
- Validação real via `run_foss_spec.yml` no branch (ver CI abaixo).

## Validacao Fase 2 (local, 2026-11-10)
- `pnpm vitest run app/javascript/survey`: 4 arquivos, 35 testes passed (inclui os 3 novos de `disable_feedback`).
- `eslint` nos 2 arquivos tocados: 0 errors (1 warning pré-existente em `Response.vue:73`, `$t` dinâmico original).
- `ruby -c` (container rails, só leitura): Syntax OK nos 11 arquivos Ruby novos/tocados; `node --check` OK no script do `Response.vue` e no spec.
- Backend RSpec + `run_foss_spec.yml`: pendente de disparo — sem `gh`/token neste ambiente; branch `feat/fase2-csat` (`b35f61bd`) já no remoto; disparar com `gh workflow run run_foss_spec.yml --ref feat/fase2-csat --field full=true`.

## Fase 2 rodada 2 · modo whatsapp/link/off + entrega da pesquisa (branch feat/fase2-csat)

- Base: main remota `57d4cf6365e90d8902971938e39db48f13c6ab5c` (fetch ok, ls-remote == origin/main, sem movimento desde a rodada 1 — sem rebase); produção `5752fd8dd9477761af9b8b3c8d0671872970977e` ancestral de `origin/main` (exit 0).

## Fixed (bug crítico de entrega)
- `OutboundDispatch.claim!` estacionava a pesquisa (escopo `closed` pós-resolução). Agora `claim_sql` é montado com as tabelas vivas dos modelos (+ exceção Fase 2: `input_csat` com protocolo e escopo `closed` despacha; qualquer outra saída em `closed` continua `parked`). `G0Adapter.patch_outbound_claim` virou no-op (sem constante para remapear); semântica de enforcement preservada por ambiente (g0: `<> 'maintenance'`; produto: `= 'enforce'`).

## Added
- `POST /connecta/v1/csat_config` (HMAC plataforma→fork, `Connecta::V1::CsatConfigController#update`): body `{account_id, inbox_id, mode: whatsapp|link|off, window_minutes?}` → atualiza a inbox (só se marcada) `csat_survey_enabled` (false no `off`) e `csat_config {mode, display_type star, disable_feedback true, window_minutes}` (padrão 60); 200 devolve a config aplicada; 404 `inbox_not_enforced`; 422 `invalid_mode`/`invalid_window_minutes`; idempotente. Rota em `config/routes.rb` + `route_inventory_spec`.
- Modo whatsapp: `CsatPolicy::WHATSAPP_MESSAGE_TEMPLATE` ("...Responda esta mensagem com uma nota de *1 a 5*..."), sem link no presenter/builders; `survey_mode`/`whatsapp_mode?` na política.
- `Connecta::Runtime::CsatSentJob`: após a pesquisa aceita no claim (`resolve!` com `accepted`), posta `POST /attendance/v1/csat/sent` `{account_id, conversation_id: display_id, case_protocol, survey_uuid, contact_id, mode, sent_at}` — sem telefone/nome, retry 24x.
- Specs: claim (pesquisa final despacha × texto/origem/sem-protocolo estacionam × controle active), `CsatSentJob` (contrato exato), texto whatsapp sem link, `PUT` público com nota no modo whatsapp (resposta sem comentário + push `csat`), endpoint (8 exemplos).

## Deploy (atualizado — WP aplica; fallback manual)
- Produção será configurada pelo WP via `POST /connecta/v1/csat_config` (sem intervenção no fork). Fallback manual (só se o endpoint indisponível), rails runner:
```ruby
inbox = Inbox.find(9)
inbox.update!(
  csat_survey_enabled: true,
  csat_config: inbox.csat_config.merge(
    'mode' => 'link', 'display_type' => 'star', 'disable_feedback' => true, 'window_minutes' => 60
  )
)
```

## Validacao
- `ruby -c` (container rails, só leitura): Syntax OK nos 10 arquivos Ruby novos/tocados; linhas ≤150.
- Backend RSpec + `run_foss_spec.yml`: ver CI abaixo.
