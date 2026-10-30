# Evidência — deploy local fork-web/fork-worker (fase D.1) — 2026-10-27

Fonte única dos comandos, resultados e limites deste passo de deploy.
Não reimplementa fase I; refere código aprovado pelo juiz (fase I) sem recontar história.

## 1. Repos / HEAD / sujeira

- fork: cwd/top-level `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`, HEAD `beaf180d5b65000f5c4a10dfa15ebe486f7c1b23`.
- monorepo: cwd `/home/thanos/conectacidade/.worktrees/app-solicitacoes`; top-level observado nesta sessão é o próprio cwd (difere do Explorer anterior que reportou `/home/thanos/conectacidade`; registrado sem mudar repo/branch). Branch `feat/app-solicitacoes`, HEAD `f5ae41f0c1c3c059620cf6c95eb62167790bc2d5`.
- `git status --short` de ambos ao final em §9 (código aprovado intocado; só `.context/*` deste passo).

## 2. Build anterior (pré-reinício)

- Job `sh_17b3f351c00156I3qjpUKw4Edf`: output vazio (`0 bytes`, `2026-10-27 02:45`); nenhuma thread `docker build/buildx/buildkit` ativa (`ps aux | grep docker build` vazio; dockerd pid 1734 desde Oct25).
- Decisão: build antigo indisponível; nova imagem construída agora via camada mínima de código (detalhe local reversível).

## 3. Docker / compose

- `docker context ls`: `default` = `unix:///var/run/docker.sock` (local), único endpoint.
- Compose canônico: `/home/thanos/chatwootnext-connecta-g0-prep/deploy/e2e/compose.yml`.
- Entrypoint/command atuais (sem migrations/schema/seed): web `["bundle","exec","rails","s","-b","0.0.0.0","-p","3000"]`; worker `["bundle","exec","sidekiq","-C","config/sidekiq.yml"]`; healthcheck web `wget http://127.0.0.1:3000/api`.

## 4. Base / nova imagem

- Base: tag `connecta-e2e-fork:rollback-2026-10-26-c82f2d5` ID verificado `sha256:c82f2d5330ef89f1b102c521bff324bc8c34811c36f696f4f160fe48c6f8af9e` (sem pull/remotos).
- Compatibilidade comprovada (host tree × in-container base): `config/initializers/connecta_runtime.rb` `2d59c...9011f9b`, `runtime/feature.rb` `fd9db...3ca094`, `runtime/g0_adapter.rb` `ffff9...845ff`, `runtime/installer.rb` `be520...0aaa3`, `runtime/transfer_transaction.rb` `c433b...398d8` — idênticos. Só os 9 arquivos aprovados divergiam + `native_admin.rb` ausente na base.
- Build mínimo (Dockerfile temporário em `/tmp/opencode/fork-layer`, sem editar repo): `FROM rollback-tag + COPY app → /app/app` (workdir `/app`; 10 arquivos .rb aprovados, sem specs/.context/.env/segredos).
- Sintaxe pré-build: `ruby -c` (Ruby do container via stdin) OK nos 10 arquivos.
- `docker build --pull=false -t connecta-e2e-fork:local -t connecta-e2e-fork:20261027-local-coded-layer /tmp/opencode/fork-layer`: `BUILD-EXIT:0`.
- Nova imagem: ID `sha256:a9d4a8c733e9c14e65fccdabc060f234d229ab5823eddfd450410d761564b7b5` (ambas tags, criado `2026-10-27 10:16:50 UTC`).
- Rollback preservado: tag `connecta-e2e-fork:rollback-2026-10-26-c82f2d5` intacta (mesmo ID). Sem criar nova tag rollback. Sem prune/apagar imagem.

## 5. SHA dos 10 Ruby aprovados

Host tree (antes) = contexto build = dentro dos 2 novos containers:

- `connecta_scopes_controller.rb` `546d2f…aa869f`
- `runtime/transfer_policy.rb` `45c6e6…964a62a7`
- `scope/admin_metadata_delivery_guard.rb` `c32f2c…5581e0c`
- `scope/conversation_http_hook.rb` `911bf1…f9b42b`
- `scope/conversation_query.rb` `d579e7…99fc9331`
- `scope/delivery_check.rb` `fe95dd…d3ca165`
- `scope/delivery_context.rb` `928e3b…27d09`
- `scope/gate.rb` `3f163d…599b5d5a`
- `scope/socket_hook.rb` `17f559…c2b8aa6`
- `scope/native_admin.rb` `a259cb…4b8104`

## 6. Recreate restrito + verificação

- Comando: `docker compose -p connecta-e2e -f <compose> up -d --no-deps --force-recreate fork-web fork-worker` → `UP-EXIT:0` (só os 2 serviços; sem up geral/down/restart de dependências; volumes/ports/LAN inalterados; aviso de orphans ignorado, sem `--remove-orphans`).
- Pós-recreate: web `a9cbeb800938` imagem `a9d4a8…` `Up (healthy)`; worker `ea4b0fe40f00` imagem `a9d4a8…` `running` `RestartCount=0`. Healthcheck real: `wget /api` in-container `EXIT:0`.
- Runtime/helper no novo web (rails runner, sem consultar dados reais): `NativeAdmin=Connecta::Scope::NativeAdmin`, `Gate=Connecta::Scope::Gate`, `FeatureFlag=true` (nota: collation warning do Postgres no stderr, só aviso, sem ação).
- Worker sem restart loop. Novos containers usam a MESMA nova imagem.

## 7. Invariância (baseline pós-reinício → pós-deploy)

- Recriados nesta fase: SOMENTE `connecta-e2e-fork-web` (`3741ec33…` → `a9cbeb800938`) e `connecta-e2e-fork-worker` (`b0244da1…` → `ea4b0fe40f00`). Demais IDs/images iguais ao baseline (fora a mudança de imagem/ID dos 2).
- wp: ID `048682bdd1df…` imagem `e3333b25…` `running (healthy)` — intacto.
- Baileys-api `70e0bd537c73` / baileys-redis `1192d11045c1` / fork-postgres `48afd165c8b4` / fork-redis `e1776942471…` / wp-postgres `39b7a37d0cc5` / wp-redis `11c57ecbebc2` — IDs/images inalterados.
- B5 (`chatwootnext-rails-1 96bb5c3eea76`, stack `chatwootnext:local`) Up 40h healthy — preservado.
- 3 deploy preexistentes (`deploy/baileys-api/docker-compose.yml`, `deploy/e2e/README.md`, `deploy/e2e/compose.yml`): hashes idênticos antes/depois (ver §9). Monorepo baseline intocado por esta fase.

## 8. Limites

- Deploy smoke (health/SHA/runtime introspection). E2E funcional manual segue pendente (não executado: sem enviar mensagens/transfers reais nem enfileirar jobs).
- Frase histórica corrigida no changelog: hooks Connecta instalados fora de test via opt-in (`config/initializers/connecta_runtime.rb`), não "só em test".
- Falha → rollback restrito (DOCUMENTADO — NÃO EXECUTADO; nenhum comando abaixo foi rodado nesta atribuição):
  - Verificação prévia (somente leitura, numa execução futura): `docker image inspect connecta-e2e-fork:rollback-2026-10-26-c82f2d5 --format '{{.Id}}'` deve devolver `sha256:c82f2d5330ef89f1b102c521bff324bc8c34811c36f696f4f160fe48c6f8af9e`; `docker image inspect connecta-e2e-fork:20261027-local-coded-layer --format '{{.Id}}'` deve devolver `sha256:a9d4a8c733e9c14e65fccdabc060f234d229ab5823eddfd450410d761564b7b5` (nova imagem preservada — não remover).
  - Execução futura válida (exemplo, NÃO EXECUTADO): `docker image tag connecta-e2e-fork:rollback-2026-10-26-c82f2d5 connecta-e2e-fork:local && docker compose -p connecta-e2e -f /home/thanos/chatwootnext-connecta-g0-prep/deploy/e2e/compose.yml up -d --no-deps --force-recreate fork-web fork-worker` (restrito aos 2 serviços; sem editar compose, sem `up` global, sem remover imagens).
  - Verificação health após rollback (a fazer se/quando executado — NÃO executado aqui, sem alegação de teste): web `Up (healthy)` via healthcheck `/api` in-container, worker `running` com `RestartCount=0`, demais serviços inalterados.

## 9. GIT_STATUS_AFTER (sanitizado, sem segredos)

fork `git status --short` (literal, sem commit — arquivos novos seguem untracked `??`):
M .context/PROJECT_STATE.md
M app/controllers/api/v1/accounts/conversations/connecta_scopes_controller.rb
M app/services/connecta/runtime/transfer_policy.rb
M app/services/connecta/scope/admin_metadata_delivery_guard.rb
M app/services/connecta/scope/conversation_http_hook.rb
M app/services/connecta/scope/conversation_query.rb
M app/services/connecta/scope/delivery_check.rb
M app/services/connecta/scope/delivery_context.rb
M app/services/connecta/scope/gate.rb
M app/services/connecta/scope/socket_hook.rb
M deploy/baileys-api/docker-compose.yml
M deploy/e2e/README.md
M deploy/e2e/compose.yml
M spec/connecta/attachment_download_scope_spec.rb
M spec/connecta/scope_admin_metadata_pending_spec.rb
M spec/connecta/scope_policy_query_spec.rb
M spec/connecta/scope_socket_delivery_spec.rb
M spec/connecta/scope_socket_spec.rb
?? .context/changelog/CHANGELOG_2026_10_27.md
?? .context/evidence/baileys/2026-10-27-admin-native-local-deploy.md
?? app/services/connecta/scope/native_admin.rb
?? spec/connecta/native_admin_runtime_transfer_spec.rb

fork `git diff --check`: limpo (exit 0).

monorepo `git status --short` (literal, intocado por esta fase):
M apps/whatsapp-platform/src/admin/organizationAdminRoutes.ts
M apps/whatsapp-platform/src/db/repositories/attendanceOutboxRepo.ts
M apps/whatsapp-platform/src/db/repositories/orgUnitRepo.ts
M apps/whatsapp-platform/src/db/repositories/staffGrantRepo.ts
M apps/whatsapp-platform/src/db/repositories/staffIdentityLinkRepo.ts
M apps/whatsapp-platform/src/services/humanService/attendanceOutbox.ts
M apps/whatsapp-platform/src/services/humanService/routes.ts
M apps/whatsapp-platform/tests/organizationAdminRoutes.test.ts
M apps/whatsapp-platform/tests/staffIdentityLink.test.ts
?? .context/changelog/CHANGELOG_2026_10_26.md
?? .context/plans/2026-10-26-baileys-fechamento-ciclo-local.md
?? apps/whatsapp-platform/.context/changelog/CHANGELOG_2026_10_26.md
?? apps/whatsapp-platform/src/db/repositories/staffAuthEpochRepo.ts
?? apps/whatsapp-platform/src/services/humanService/aclSyncEvents.ts
?? apps/whatsapp-platform/src/services/humanService/aclSyncPublish.ts
?? apps/whatsapp-platform/tests/aclSyncProducers.test.ts
?? apps/whatsapp-platform/tests/aclSyncPublish.test.ts

monorepo `git diff --check`: limpo (exit 0; sem alteração feita aqui).
