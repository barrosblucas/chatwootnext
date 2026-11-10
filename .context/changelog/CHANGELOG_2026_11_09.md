# Changelog 2026-11-09

## Fase 1 vinculo simplificado: CI verde (provision sem senha, reativacao, lint) — 2026-11-10

- Causa (run 42725253050, backend-tests F5: 104 exemplos, 3 falhas; lint-backend: 96 ofensas, 22 novas da Fase-1):
  - provision sem `password` -> 422: `SecureRandom.base58(32)` nunca tem especial e o Devise `secure_password` exige 1 maiuscula + 1 minuscula + 1 digito + 1 especial (`config/initializers/secure_password.rb`) — `User#save!` fazia rollback e caia em 422 `provision_rejected` (mesma causa nas 2 falhas de 422: `:52` sem senha e `:91` admin_only).
  - reativar via provision -> 500: `deactivate!` destruia `AccountUser`/`InboxMember` mas mantinha `notification_settings` (unicidade `(account_id,user_id)`); no re-provision o `after_create_commit :create_notification_setting` estourava e virava 500 (log: `NotificationSetting Create` + `ROLLBACK`).
- Codigo (branch `feat/vinculo-simplificado-fase1`, sem mudar contrato de fio nem papel administrator):
  - `app/services/connecta/provisioning/agent_provisioner.rb`: `self.generate_password` (`"Aa1!" + base58(28)`, 32 chars, garante as 4 classes); `provision!` fatiado em `normalize_email!`/`validate_name!`/`find_or_create_user!`/`ensure_agent_membership!` (zera Metrics AbcSize/Cyclomatic/MethodLength); `deactivate!` passa a remover `notification_settings` da conta.
  - `app/services/connecta/runtime/acl_sync_service.rb`: `verify_link!` extrai `stale_link?` e `apply_snapshot_if_present!` (mesmo comportamento, zera CyclomaticComplexity).
- Specs (mesmas assercoes, so lint): `users_provisioning_spec.rb`: `JSON.parse(response.body)` -> `response.parsed_body` (12x), `:aggregate_failures` nos 2 exemplos com >7 expects, alinhamento `headers:`/`params:`; `runtime_acl_sync_grants_spec.rb`: `describe` passa a citar `Connecta::Runtime::AclSyncService`, `@version` vira `let(:projection)`.
- Validacao: `ruby -c` OK nos 5 RB (container `chatwootnext:local`, `--network none`); `git diff --check` limpo; `bundle exec rspec`/`rubocop` locais indisponiveis (sem Ruby/Postgres na maquina) — segue para o CI (`run_foss_spec.yml` workflow_dispatch).
- Historico: lint-backend ja falhava na main `0e4bcf18` (74 ofensas pre-existentes; branch tinha 96 = 74 + 22 da Fase-1, agora zeradas) e backend-tests passava 100% na main; security-scan falha nas duas (CVEs de Rails, pre-existente, sem upgrade).
- CI run 1 (`be5210cc`, `workflow_dispatch` 42726945083): backend-tests (0) OK — 104 exemplos, 0 falhas (3 falhas de provision zeradas); lint-backend ainda com 2 ofensas novas em `runtime_acl_sync_grants_spec.rb` (`RSpec/SpecFilePathFormat` + `RSpec/DescribeMethod`, introduzidas ao trocar o `describe` para a classe). Correcao: voltar ao `describe` string original com `# rubocop:disable RSpec/DescribeClass` (convencao ja usada em `baileys_agent_signature_spec.rb`/`outbound_dispatch_spec.rb`), mantendo `let(:projection)` no lugar de `@version`.
- CI run 2 (`23bac36e`, `workflow_dispatch` 42727859783): backend-tests (0) OK — 104 exemplos, 0 falhas; lint-backend 74 ofensas, zero nos 4 arquivos da Fase-1 (volta ao patamar pre-existente da main); security-scan segue falhando (CVEs de Rails, pre-existente). AC1+AC2 atendidos, contrato inalterado.

## Intenção da feature
Corrigir o popup enganoso "You are not authorized to do this action" exibido para o
agente legítimo ao abrir `settings/connecta`: o vínculo de identidade (POST
`identity_link`) sempre funcionou, mas o GET `outbound_dispatches` da mesma tela
exigia `admin_nominal` e a negação Pundit virava 401 pelo handler global — e o
frontend só suprime 403. A correção responde 403 local no filtro, sem tocar o
handler global: login válido sem `admin_nominal` vê 403 silencioso, sessão ausente
continua 401. Correção 02 (spinner/caixas) fica para o próximo passo no mesmo
worktree; sem deploy, sem mutação de produção.

## Correção 01 — dispatches 403 silencioso para agente vinculado

### Contexto
`ConnectaSettings.vue` faz GET `outbound_dispatches` no mount para todo usuário
logado; o endpoint exige `Connecta::Scope::Projection#admin?` e levantava
`Pundit::NotAuthorizedError`, convertido em 401 pelo `RequestExceptionHandler`
global. O vínculo de identidade (POST separado) não era afetado — por isso o
usuário conseguia se vincular mesmo com o popup.

### Mudanças
- `app/controllers/api/v1/accounts/connecta/outbound_dispatches_controller.rb`:
  `authorize_nominal_admin!` resgata `Pundit::NotAuthorizedError` no próprio
  filtro e responde `403 { error: 'Admin nominal permission required' }` — mesmo
  padrão de `acl_controller.rb` e `scoped_inboxes_controller.rb`. Vale para GET
  (index) e PATCH (resolve), que compartilham o filtro. Handler global intacto;
  `authenticate_user!` continua 401 para sessão ausente/inválida; acesso a dados
  e auditoria inalterados para `admin_nominal`.
- `spec/requests/connecta/outbound_dispatches_authorization_spec.rb` (novo):
  agente vinculado 403 sem chave `dispatches`; PATCH do agente 403 sem mutar
  estado e sem `AccessAudit`; nominal lista 200; nominal resolve 200 com
  `connector_message_id`; sem token 401.
- `app/javascript/dashboard/routes/dashboard/settings/connecta/specs/ConnectaSettings.spec.js`
  (novo): 403 não dispara `useAlert`; 500 exibe o erro; nominal renderiza a linha.

### Validação
- `git diff --check` local OK; sintaxe do spec JS via `node --check` OK.
- Sem Ruby/DB/Redis/serviços neste ambiente: specs Rails e suite frontend rodam
  só no GitHub Actions (`scripts/connecta/g0_test_env.sh --spec`; affected/full
  via `run_foss_spec.yml`). `node_modules` ausente — sem vitest/eslint locais,
  sem installs.
- Sem build, sem deploy, sem commit/push, sem mutação de produção ou roles.

## Correção 02 — inbox list não prende mais no spinner quando o cache trava

### Contexto
`inboxes/get` (store `inboxes.js`, `isFetching` com `try/catch` que já limpa o
flag em sucesso/erro) chama `InboxesAPI.get(true)` → `CacheEnabledApiClient.get`
→ `getFromCache`, que aguardava `DataManager.initDb()` sem limite: um `openDB`
bloqueado (ex. outra aba com versão antiga) nunca resolvia e nenhum request
(`cache_keys` ou lista) era emitido — spinner infinito. Store não precisou de
mudança (só `isFetching` já reseta nos dois caminhos); nenhum inbox/DB/registro
foi criado, alterado ou excluído.

### Mudanças
- `app/javascript/dashboard/helper/CacheHelper/DataManager.js`:
  `initDb` com timeout limitado (`DATA_MANAGER_INIT_TIMEOUT_MS = 5000`),
  compartilha `initPromise` entre leituras concorrentes, mantém sucesso tardio
  em `this.db` sem `unhandled rejection`, libera retry na próxima leitura;
  bookkeeping de `localStorage` em `try/catch`; nada é apagado.
- `app/javascript/dashboard/api/CacheEnabledApiClient.js`:
  `getFromCache` extrai probe somente-leitura `loadFromCache` (open, key check,
  linhas locais) sob `withCacheReadTimeout` (`CACHE_READ_TIMEOUT_MS = 8000`);
  timeout/falha local → `refetchAndCommit()` (rede autenticada existente, mesma
  URL/tenant); erro genuíno de rede/autorização continua rejeitando (sem dado
  stale como sucesso); `cacheModelName` ausente continua lançando alto.
  Genérico para inboxes/labels/teams/canned (isolamento por conta preservado).
- `app/javascript/dashboard/api/specs/CacheEnabledApiClient.spec.js` (+4):
  init travado → rede; 2 leituras concorrentes travadas → rede (2 requests);
  leitura local rejeitada → rede com DB intacto; rede 403 com key movida →
  rejeita (sem stale).
- `app/javascript/dashboard/helper/specs/CacheHelper/DataManagerTimeout.spec.js`
  (novo, `idb` mockado): open travado rejeita no timeout e permite retry;
  sucesso tardio é guardado sem rejection; concorrentes compartilham 1 open.

### Validação
- `git diff --check` OK; sintaxe ESM dos 4 arquivos via
  `node --input-type=module --check` OK.
- `node_modules` ausente: vitest/eslint locais impossíveis sem install
  (proibido); specs novas + afetadas (`CacheEnabledApiClient.spec.js`,
  `DataManger.spec.js`, `inboxesCacheKey.spec.js`, `inboxes.spec.js`) pendentes
  no GitHub Actions. Sem browser/login real: validação de UI segue pendente.
- Sem build, serviços, deploy, commit/push; correção 01 intacta; nenhuma
  mutação de produção, DB, inbox ou roles.

## Fase atual
Correção 01 (403 silencioso) e 02 (spinner/cache limitado) prontas no worktree
isolado, sem commit/push/deploy; suíte JS e validação de UI pendentes no CI/browser.
Correções antes de qualquer exclusão, conforme pedido do usuário.

## EE isolado — workflow `publish_ee_github_docker.yml` adaptado (preparado, sem push/build/deploy)

### Contexto
Branch `fix/chatwoot-painel-20261109` (de 15fa2b33, correções 01 popup 403 e 02
spinner/cache acima) precisava de workflow EE isolado próprio. O workflow
isolado anterior (`ci/ee-build-15fa2b33`, commit c740091) construiu b59d a
partir de 15fa com tags protegidas intactas, mas tinha branch e SOURCE_SHA
fixos — foi usado só como referência, sem alterar aquele worktree.

### Mudanças (só `.github/workflows/publish_ee_github_docker.yml`, sem commit)
- `on:` só `workflow_dispatch` (gatilho `release` removido); concorrência
  dedicada `ee-build-fix-chatwoot-painel-20261109`.
- Guarda: só dispatch manual na branch exata `fix/chatwoot-painel-20261109`
  (ref/event via `env:` mapeado, sem injeção inline).
- Fonte imutável = `github.sha` do dispatch: checkout `ref: ${{ github.sha }}`
  com `fetch-depth: 0`; valida HEAD == dispatch SHA e descendente da base
  implantada 15fa via `git merge-base --is-ancestor`; `enterprise/` exigido.
  Mover a branch entre push e dispatch não muda o build.
- Tag única nova `ee-src-<SHA cheio>` derivada do dispatch SHA em cada job
  (nada fixo); pré-voo recusa se a tag já existir (fail closed).
- Build por plataforma com `push-by-digest` (sem tags), provenance no padrão
  do builder (nunca `false`); verificação na imagem por digest: `CW_EDITION=ee`,
  `/app/enterprise` presente, `/app/.git_sha` == SHA fonte.
- Merge cria UMA tag (`-t $REPO:$EE_TAG`); `latest-ee`,
  `fix-producao-20261106-ee` e tags CE nunca escritas; baseline/pós-checagem
  por digest canônico de manifesto (`^Digest: sha256:…`, 1 único) fail closed
  antes e depois da publicação.
- Bug anterior evitado: nenhum `env:` de job usa contexto `env` (só passo a
  passo / `$VAR` de shell); summary registra source SHA e workflow SHA
  separados + digests + identidade de deploy por digest (tags são mutáveis).
- Correções 01/02, specs e testes intactos; registrado só em main do repo
  (`publish_ee_github_docker.yml`) sem tocar scanner/lint/test workflows.

### Validação (sem serviço/rede, sem build/imagem, sem installs)
- `python3 yaml.safe_load`: nome/jobs/gatilho OK; `git diff --check` OK.
- Cheques estruturais: sem `release`, branch exata, base 15fa, tag dinâmica,
  checkout por SHA + `fetch-depth: 0`, ancestralidade, push-by-digest, sem
  `provenance:false`, `-t` único sem protegidas/CE, digest canônico x4+,
  verificação EE/`enterprise`/`.git_sha`, summary com ambos SHAs — PASS.
- Simulações: guarda aceita branch+dispatch corretos e recusa `main`;
  derivação `ee-src-<sha>`; `merge-base --is-ancestor 15fa HEAD` OK;
  `git status` confirma correções 01/02 preservadas.
- Pendente no GitHub (requer dispatch autorizado): focused RSpec de
  autorização com DB/Redis descartáveis
  (`outbound_dispatches_authorization_spec.rb`); vitest frontend de cache e
  connecta (`CacheEnabledApiClient.spec.js`, `DataManagerTimeout.spec.js`,
  `ConnectaSettings.spec.js`, afetados `inboxes*`); build EE isolado com
  verificação de digest e tags protegidas. CI geral segue com 74 lints de
  backend e 23 advisories (1 crítico, 6 altos) conhecidos — sem ignorar
  checks nem declarar cobertura verde; nova exceção/autorização antes do
  rollout se o build mudar a imagem.

### Estado
Workflow PREPARADO no worktree, não commitado, sem push/dispatch/build/deploy
e sem mutação de produção. Deploy só após correções validadas; exclusões só
depois da produção, conforme pedido do usuário.

## Correção de imports do spec de autorização (sem enfraquecer testes)

### Contexto
`spec/requests/connecta/outbound_dispatches_authorization_spec.rb` referenciava
`../support/connecta/g0_target_guard` (= `spec/requests/support/...`,
inexistente) e `support/g0_scope_schema` / `support/g0_scope_fixture` (=
`spec/requests/connecta/support/...`, inexistente). Convenção provada pelos
vizinhos: `spec/requests/connecta/route_inventory_spec.rb` usa
`../../support/connecta/g0_target_guard`; specs sob `spec/connecta/` usam
`../support/...` + `support/...` porque estão um nível acima. Fixtures reais em
`spec/support/connecta/g0_target_guard.rb` e
`spec/connecta/support/g0_scope_{schema,fixture}.rb`.

### Mudanças (só o spec, sem tocar controller/cache/workflow)
- Guarda: `../../support/connecta/g0_target_guard` (resolve para
  `spec/support/connecta/g0_target_guard.rb`, mesmo `Connecta::G0TargetGuard.verify!`).
- Fixtures: `../../connecta/support/g0_scope_schema` e
  `../../connecta/support/g0_scope_fixture` (resolvem para
  `spec/connecta/support/...`, mesmos `Connecta::G0ScopeSchema.ensure!`,
  `Connecta::Scope::Installer.install!` e shared context
  `with connecta g0 scope fixture` que fornece `account`, `whatsapp_inbox`,
  `conv_a`, `agent_a`, `admin_nominal`, `json`).
- Nenhum teste enfraquecido ou excluído: 5 exemplos intactos (agente 403 sem
  `dispatches`; PATCH do agente 403 sem mutar estado nem `AccessAudit`;
  nominal lista 200; nominal resolve 200 com `connector_message_id`; sem
  token 401).

### Validação (sem serviço, sem Ruby/DB/Redis)
- Resolução de caminho no-shell: 3/3 `require_relative` resolvem para arquivos
  existentes — PASS.
- Shared context/fixtures: definição e uso 1:1, `Installer.install!` e model
  `OutboundDispatch` presentes — PASS.
- `git diff --check` limpo; Ruby indisponível neste ambiente — RSpec real
  pendente no GitHub Actions (`scripts/connecta/g0_test_env.sh --spec`).
- Sem build/install, sem commit/push/dispatch/deploy; trabalho anterior
  (correções 01/02 + workflow EE) preservado sem alteração.

## Micro-fix frontend lint (2 anotacoes CI, sem mudar runtime)

### Contexto
Run 42599061785 `lint-frontend` falhou em 2 anotacoes novas; `frontend-tests` passou. Baseline 15fa estava verde.

### Mudancas (so arquivos proprios, sem enfraquecer testes)
- `app/javascript/dashboard/api/CacheEnabledApiClient.js` (13-14): constante em uma linha `export const CACHE_READ_TIMEOUT_MS = DATA_MANAGER_INIT_TIMEOUT_MS + 3000;` (Prettier); LF preservado, sem mudanca de comportamento.
- `app/javascript/dashboard/api/specs/CacheEnabledApiClient.spec.js` (324): `Promise.reject({ response: { status: 403 } })` trocado por `Error` com mesma propriedade `response.status 403` via `Object.assign`; assercao `rejects.toMatchObject({ response: { status: 403 } })` intacta, semantica de falha de rede 403 preservada.

### Validacao (sem servico, sem installs/builds)
- `git status --short` antes limpo; depois so os 2 arquivos proprios modificados.
- `node --check` nos 2 arquivos: OK.
- `git diff --check`: limpo.
- `node_modules` ausente: eslint/vitest locais impossiveis (sem installs); suite real pendente no GitHub Actions.
- Sem commit/push/deploy; arquivos do outro front (CI/test-support) intocados.

## Correcao test-only do DB comum (sem tocar producao; specs de servico pendentes no Actions)

### Contexto
Run full 42599061785: 7 shards comuns falharam (~1798 erros) por tabela ausente `connecta_g0_scoped_inboxes`. Causa: DB comum tem so tabelas produto `connecta_*` (schema:load); com feature desligada no CI comum, `G0Adapter.install!` nunca roda e os modelos G0 mantem `table_name connecta_g0_*`. O `ActionCableListener#message_created` chama `Projection.marked?` incondicionalmente, e qualquer spec transacional que cria Message quebra no lookup. F5 usa DB isolado proprio e segue verde. Producao (rails/sidekiq) segue nas tabelas produto com enforcement; `Projection.marked?` sem fail-open preservado (erro propaga).

### Mudancas (so CI/test-support, sem producao/autorizacao)
- `spec/support/connecta/common_product_tables.rb` (novo, TEST-ONLY): com `CONNECTA_COMMON_PRODUCT_TABLES=1`, so em `Rails.env.test?` e fora do alvo F5, retargeta os modelos G0 via `G0Adapter::TABLES` as tabelas produto existentes; sem prepend/hooks, sem flip de flag, sem mudar autorizacao. Tabela produto ausente levanta alto (sem mock/skip). Inativo no F5/producao.
- `spec/lib/connecta_common_product_tables_spec.rb` (novo, runner comum): comum mapeia para produto sem hooks; F5 intacto mesmo com flag; tabela ausente falha visivel; `Projection.marked?` propaga erro e fonte sem `rescue false`. Sanitizer de midia e permissoes existentes preservados; sem skip nem reducao de shard.
- `.github/workflows/run_foss_spec.yml`: so adiciona `CONNECTA_COMMON_PRODUCT_TABLES: '1'` ao env de `Run common backend specs`. Triggers, gates, lint, security-scan, selecao RSpec, runner F5 e producao intocados; baseline 74 RuboCop/23 advisories sem supressao.

### Validacao
- `git diff --check`: limpo; YAML do workflow via `yaml.safe_load`: OK; cheques estruturais (sem `prepend`/install de producao no helper, sem `G0TargetGuard.verify!` no spec comum, triggers intactos): PASS.
- Sem Ruby/DB/Redis/servicos, sem builds/installs, sem commit/push: RSpec real (incl. novo spec + suite comum/F5) pendente no GitHub Actions. Arquivos do front paralelo (`CacheEnabledApiClient.js` + spec) intocados.

## Fix test-only colisao de fixture no spec F5 de outbound_dispatches (sem tocar producao; RSpec real pendente no Actions)

### Contexto
Run full 42619921521 shard7 F5: os 5 exemplos de `spec/requests/connecta/outbound_dispatches_authorization_spec.rb` falhavam com `PG::UniqueViolation` no `dispatch.create!` explicito. Causa: neste shard o `transfer_activation` instala o `MessageHook` (`Message.prepend`) e o `runtime_acl_sync` retargeta `OutboundDispatchRecord` via `G0Adapter` para a mesma tabela produto `connecta_outbound_dispatches` (unique em `message_id`); o hook ja insere a linha queued de `outgoing_message` antes do fixture. Composicao anterior (shard6, sem hook) passava. Sem regressao de producao: controller/autorizacao intactos.

### Mudancas (so o spec alvo, sem codigo de producao/autorizacao)
- `spec/requests/connecta/outbound_dispatches_authorization_spec.rb` (fixture `uncertain_dispatch`): `create!` direto trocado por `find_or_initialize_by(message_id:)` + atribuicao (`conversation`, `state uncertain`, `attempted_at`) + `save!`. Sem hook cria a linha uncertain; com hook reaproveita a linha queued e a promove a uncertain. 5 assercoes reais de endpoint intactas (agente 403 sem `dispatches`; PATCH do agente 403 sem mutar estado nem `AccessAudit`; nominal lista 200; nominal resolve 200 com `connector_message_id`; sem token 401); sem stub de controller/autorizacao, sem enqueue stubado.

### Validacao
- `git diff --check`: limpo; cheques estruturais no-shell: `find_or_initialize_by` presente, `create!` duplicado removido, 5 exemplos e todas as assercoes de status/auditoria intactos, sem stubs, sem arquivos de producao tocados — PASS.
- Ruby indisponivel neste ambiente (`ruby: command not found`); sem DB/Redis/servicos, sem builds/installs, sem commit/push: RSpec real pendente no GitHub Actions. Arquivos dos fronts paralelos (`connecta_transfers_controller_spec.rb`, `whatsapp_spec.rb`, `connecta_common_product_tables_spec.rb`, `common_product_tables.rb`) preservados sem alteracao.

## Fix test-only setup latente: helper de rota + fixtures (sem tocar producao; RSpec real pendente no Actions)

### Contexto
Run full 42619921521: shard1 com 2 NoMethodError no helper inexistente de rota GET e 8 PG NotNullViolation porque `find_or_create_by!` salva antes de atribuir `value`; shard6 com falso-positivo no spec Whatsapp (expectativa negativa armada antes da criacao lazy do `channel`, cujo account-dispatched era lido como evento sob teste). Mapeamento test-only anterior apenas revelou esses testes; nenhuma producao tocada.

### Mudancas (so os 2 specs proprios, sem producao/autorizacao)
- `spec/controllers/api/v1/accounts/conversations/connecta_transfers_controller_spec.rb`: 6 chamadas GET trocadas para o helper Rails correto de singular resource (`destinations_api_v1_account_conversation_connecta_transfer_url`), mesmos argumentos; 3 `find_or_create_by!` trocados por `find_or_initialize_by(...).update!(value: ...)`, padrao ja usado no repo. Todas as assercoes de autorizacao/secret-leak intactas.
- `spec/models/channel/whatsapp_spec.rb` (exemplo ~677): `channel` realizado antes de armar `expect(dispatcher).not_to receive(:dispatch)`; operacao e assercoes inalteradas.

### Validacao
- `git diff --check`: limpo; Ruby indisponivel neste ambiente; sem DB/Redis/servicos, sem builds/installs, sem commit/push: RSpec real pendente no GitHub Actions. Arquivos dos fronts paralelos (`outbound_dispatches_authorization_spec.rb`, mapper/test-support) preservados sem alteracao.

## Micro-fix RuboCop test-only: 4 ofensas novas do mapper comum (sem tocar producao; RSpec/RuboCop reais pendentes no Actions)

### Contexto
Run 42619921521 em a45a518: RuboCop 78 vs baseline 74 — 4 ofensas novas so no mapper test-only comum: spec linhas 23/24 Style/FetchEnvVar, linha 25 Rails/IndexWith, helper linha 15 Style/ClassAndModuleChildren. Scan segue 23 advisories ja aceitos.

### Mudancas (so os 2 arquivos proprios, sem enfraquecer testes)
- `spec/lib/connecta_common_product_tables_spec.rb`: 2x `ENV[key]` -> `ENV.fetch(key, nil)` (semantica unset preservada); `keys.to_h { |model| [model, model.table_name] }` -> `keys.index_with(&:table_name)` (equivalente). Todas as assercoes intactas, sem disables.
- `spec/support/connecta/common_product_tables.rb`: `module Connecta` + `module CommonProductTables` -> compacto `module Connecta::CommonProductTables` com indentacao/end ajustados. Flag explicita CI-only, isolamento F5, fail-closed de tabela ausente e comportamento de producao preservados.

### Validacao
- `git status --short` capturado antes/depois (arquivos de fronts paralelos intocados).
- `git diff --check`: limpo.
- `ruby -c` indisponivel neste ambiente (`ruby: command not found`); sem builds/installs/servicos, sem commit/push: RuboCop/RSpec reais pendentes no GitHub Actions.

## Micro-passo: commit fba7bf42 + full Actions + EE isolado (sem deploy; 1 falha funcional restante)

### Contexto
Commit `fba7bf42` (`test(connecta): fix F5 duplicate dispatch fixture, transfer route/config setup, whatsapp lazy channel, rubocop test-only offenses`) empurrou os 6 arquivos autorizados do branch isolado `fix/chatwoot-painel-20261109` (sem tocar main; repo original intacto em `15fa2b33` com trabalho Baileys preservado). Disparos autorizados: full `run_foss_spec.yml` (`full=true`) e `publish_ee_github_docker.yml` no SHA `fba7bf42`.

### Resultados
- Full FOSS run https://github.com/barrosblucas/chatwootnext/actions/runs/42628041828 (head `fba7bf42`): plan success; lint-frontend success; frontend-tests success (487 files, 4964 passed, 23 skipped); backend shards 0/2/3/4/5/6/7 success — shard7 F5 com 5 auth asserts do `outbound_dispatches_authorization_spec` verdes (duplicate-message resolvido), shard6 whatsapp lazy verde.
- backend-tests (1): 1 falha restante — `connecta_transfers_controller_spec.rb:267` "maps gateway conflict to 409": esperava `duplicate transfer`, obteve `Connecta gateway returned an error` (status 409 passou; corpo do stub 409 sem Content-Type, HTTParty nao parseia -> produto inalterado, stub latente desmascarado pelo fix NotNull). As 10 falhas anteriores do shard1 (2 rota + 8 NotNull) resolvidas; sem skip/enfraquecimento.
- lint-backend failure = baseline aceito: 74 offenses (era 78; 0 nos 5 arquivos tocados). security-scan failure = baseline aceito: bundle-audit 23 advisories (1 critical/6 high), Brakeman 41 warnings.
- EE run https://github.com/barrosblucas/chatwootnext/actions/runs/42628045237 (head `fba7bf42`): success (guard, preflight, amd64, arm64, merge). Tag isolada `ee-src-fba7bf429fa63c99261c51475a3a92738c4c99a3`; index `sha256:0ba0c593ab5347ebc9308e68d40745df5356a8c54b42f7e9e4b29b524a65986d`; amd64 `sha256:fdc0605a49a33b51e95290cc235f466b27b5e7ef0d23fd1f897f2ddfc8f034c0`; arm64 `sha256:5da2136a9e493119cbcbfeaf6715614042ae6d37c333a86f6180e8c4bdf92a39`; source `fba7bf42` descende de `15fa2b33` com enterprise/; in-image CW_EDITION=ee, /app/enterprise presente, /app/.git_sha == source (ambas archs); protected tags latest-ee + fix-producao-20261106-ee inalteradas pre/post. Nenhum deploy, remocao ou mudanca de dados.
- Follow-up necessario (fora deste passo): 1-liner no stub 409 (Content-Type json) + novo commit/dispatch; sem esse verde, sem deploy.

## Micro-fix gateway 409 fixture Content-Type (test-only; sem tocar producao)

### Contexto
Run full 42628041828 em `fba7bf42`: shard1 com 1 falha em `connecta_transfers_controller_spec.rb:267` "maps gateway conflict to 409" — status 409 passou, mas corpo esperado `duplicate transfer` caiu em fallback generico. Causa: stub WebMock 409 sem `Content-Type`, HTTParty devolve String sem parse; gateway Express real usa `res.status(...).json(...)` que envia `application/json; charset=utf-8`. Produto inalterado vs 15fa.

### Mudancas (so o stub, sem enfraquecer testes)
- `spec/controllers/api/v1/accounts/conversations/connecta_transfers_controller_spec.rb` (~269): `to_return` do stub 409 ganha `headers: { 'Content-Type' => 'application/json; charset=utf-8' }`. Payload `duplicate transfer`, status 409 e assercoes exatas intactos; sem mudanca de controller/gateway.

### Validacao
- `git diff --check`: limpo; Ruby indisponivel neste ambiente; sem builds/installs/servicos: RSpec real pendente no GitHub Actions (full + regressao do spec alvo). Nota CI anterior preservada.

## Vinculo simplificado fase 1: endpoints Connecta de provisionamento de agente — 2026-11-09

- Causa: pareamento por codigo de 5 min trabalhoso e com erros; WP passa a cadastrar uma vez no painel e o fork provisiona o agente via HMAC (fase 1; sem SSO).
- Codigo (worktree `feat/vinculo-simplificado-fase1` sobre `origin/main` `0e4bcf18`, sem commit):
  - Novo `app/services/connecta/provisioning/agent_provisioner.rb`: `provision!` (normaliza email strip+downcase; encontra via `User.from_email` ou cria com `skip_confirmation!`; existente nunca tem senha/nome alterados; `AccountUser` criado como `agent`, papel existente preservado; `InboxMember` nas caixas da conta marcadas em `connecta_scoped_inboxes` com `enforcement != admin_only` e `maintenance = false` — mesmo recorte de `conversation_query.rb:59`; erro SAML multi-conta espelha `enterprise/agent_builder.rb` → `ProvisionRejected`), `set_password!` (só `agent`; 12..128 chars; confirma se pendente; `tokens = {}`), `deactivate!` (remove `InboxMember` da conta via `destroy_all`, destrói `AccountUser` — `Agents::DestroyJob` completa a limpeza sem apagar o `User` — e zera tokens; idempotente).
  - Novo `app/controllers/connecta/v1/users_controller.rb` (`Connecta::V1::BaseController`: HMAC + `account_id` 403): `POST /connecta/v1/users/provision` → 200 `{chatwoot_user_id, user_created, membership_created, role, inbox_ids_added}` / 422 `{error: provision_rejected, reason}`; `POST /connecta/v1/users/:user_id/password` → 204 / 409 `{error: not_agent}` / 404 / 422 `{error: invalid_password, reason}`; `POST /connecta/v1/users/:user_id/deactivate` → 200 `{deactivated: true}` / `{already_inactive: true}` / 409.
  - `config/routes.rb` (bloco Connecta): 3 rotas; `spec/requests/connecta/route_inventory_spec.rb`: `connecta/v1/users` no inventario.
  - `.github/workflows/publish_ee_github_docker.yml`: guard passa a aceitar `main` além de `EXPECTED_BRANCH` (`fix/chatwoot-painel-20261109`); `workflow_dispatch` only mantido.
  - Senhas nunca logadas: `password` ja consta em `filter_parameters` (`config/initializers/filter_parameter_logging.rb`); spec cobre `ParameterFilter`.
- Regressao: novo `spec/requests/connecta/users_provisioning_spec.rb` (16 exemplos: cria/reusa/admin-mantem-papel/idempotencia/escopo admin_only excluido/HMAC 401/conta 403; senha agente 204+tokens zerados/admin 409/fora-da-conta 404/curta 422; desativa mantem User+outra-conta/idempotente/admin 409/reativa via provision; filtro de password).
- Validacao: `ruby -c` OK nos 4 RB alterados/criados (container `chatwootnext:local` readonly, `--network none`); `git diff --check` limpo. NAO executado: `bundle exec rspec` (sem Ruby/Postgres/Redis locais; specs para o CI do GitHub Actions) e `bundle exec rubocop` (rubocop ausente na imagem). Sem commit.
- Historico: entrega iniciada sobre base stale `c058826e` (remote-tracking desatualizado; 47 commits atras, sem codigo do painel); rebaseada para `0e4bcf18` via `stash push -u` + `checkout -B` + `stash pop` sem conflitos (merge limpo nos 3 arquivos rastreados; changelog do dia ja existia na nova base — esta secao foi anexada, sem sobrescrever). `AgentBuilder` nao reutilizado (exige inviter, sem senha) conforme o proprio briefing.
- Limites conhecidos: sem enforcement de limite de licenca no provision (fora do contrato); erro de licenca/SAML enterprise cai em 422 `provision_rejected`.

## ACL fork-side: lápide de grant, foto no re-vínculo, graça de heartbeat, cursor de protocolo — 2026-11-09

- Causa: auditoria fork-side (B3/B5/B15/Q7.5) sobre o contrato de fio v1 §8 + visualização de protocolos/histórico: replay de `grant.upsert` ressuscitava grant revogado; re-vínculo reativava grants obsoletos; qualquer atraso de heartbeat do WP escondia todas as conversas; página exata na cauda do lote arriscava truncar o histórico.
- Código (worktree `feat/vinculo-simplificado-fase1`, sem commit; arquivos de provisionamento da frente anterior intactos):
  - `db/migrate/20261109000000_add_grant_tombstones_to_connecta_acl.rb` (aditiva: coluna anulável `connecta_user_grants.grant_id` + índice, tabela `connecta_revoked_grants(grant_id PK, revoked_at)`) + `db/schema.rb` (versão `2026_11_09_000000`) + novo `app/models/connecta/revoked_grant.rb` (+ anotação em `user_grant.rb`).
  - `app/services/connecta/runtime/acl_sync_service.rb`: `grant.revoke` com `grant_id` apaga a linha do grant (+ legada da mesma trinca quando completa) e grava a lápide; `grant.upsert` com `grant_id` lapidado é no-op idempotente (sync segue `applied`); upsert adota a linha legada da trinca (sem duplicar); sem `grant_id`, comportamento legado (compatível com WP `c47dd1c`). `link.upsert` com `active_grant_ids` (array; vazio remove todos) apaga grants fora da lista ou legados após aplicar o vínculo; sem a lista ou com epoch velho, nada muda.
  - `app/services/connecta/scope/projection.rb`: `CONNECTA_ACL_STALE_GRACE_SEC` (padrão 900, `0` desliga); `usable?` (verificado + heartbeat dentro de TTL+graça) é a decisão única de frescor; `degraded?` sinaliza o modo degradado com `Rails.logger.warn`; `fresh?` inalterado.
  - `gate.rb:151` e `conversation_query.rb:53` passam a usar `usable?` (mesma decisão); `TransferPolicy`/`can_transfer?` seguem fail-closed no TTL (só leitura é degradada). Admin nativo/nominal, `transferred_out`, `READ_STATES` e revogação por epoch intactos.
  - `protocol_view.rb`: cursor fica no último item visível quando o lote está cheio ou a cauda não foi consumida; só lote curto totalmente consumido prova exaustão (invariante B15 explícita, sem mudar visualização).
- Regressão: novo `spec/connecta/runtime_acl_sync_grants_spec.rb` (11 exemplos: legado sem `grant_id` cria/revoga pela trinca; revoke grava lápide; lápide ignora upsert tardio; revoke idempotente; upsert adota linha legada; revoke limpa legada; foto remove obsoletos/legados e mantém listados; sem foto mantém tudo; foto vazia remove todos; epoch velho não aplica foto; revoga + re-vínculo com foto não ressuscita; `active_grant_ids` inválido rejeita). `scope_policy_query_spec.rb`: heartbeat além da graça (30 min) nega; dentro da graça (5 min) lê; revogado nega mesmo na graça; graça `0` desliga. `protocol_view_spec.rb`: página que enche na cauda do lote cheio (150 etapas, limite 100) continua sem perder/duplicar.
- Docs: `.env.example` (bloco ACL com TTL+graça), `docs/runbooks/connecta-baileys-saude.md` §5.1b, `.context/architecture.md` (seção ACL do vínculo).
- Validação: `ruby -c` OK nos RB alterados/criados (container `chatwootnext:local` readonly, `--network none`); `git diff --check` limpo. NÃO executado: `bundle exec rspec` (sem ambiente de teste local; segue para o CI) e rubocop. Sem commit.
