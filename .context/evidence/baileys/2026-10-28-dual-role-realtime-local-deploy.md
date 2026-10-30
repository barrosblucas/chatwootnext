# Evidência — deploy local fork-web/fork-worker fase D.1 (fix C.1 dual-role realtime) — 2026-10-28

Fonte única dos comandos, resultados e limites deste passo de deploy.
Não reimplementa nem retesta C.1 (105 specs + lint + juiz APPROVED em passo anterior); só implanta a camada aprovada.

## 1. Repos / HEAD / sujeira (antes; sem checkout/limpeza, sem commit)

- fork: cwd/top-level `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`, HEAD `beaf180d5b65000f5c4a10dfa15ebe486f7c1b23`.
- monorepo: cwd `/home/thanos/conectacidade/.worktrees/app-solicitacoes`; top-level observado nesta sessão é o próprio cwd. Branch `feat/app-solicitacoes`, HEAD `f5ae41f0c1c3c059620cf6c95eb62167790bc2d5`.
- `git status --short` de ambos antes = baselines do PRE-TASK STATE (código aprovado intocado; só `.context/*` deste passo). Pós-deploy literal em §9.
- `git diff --check` limpo nos dois repos (antes e depois).

## 2. Docker / compose (somente leitura)

- `docker context show` = `default`; endpoint `unix:///var/run/docker.sock` (local).
- Compose canônico ABSOLUTO: `/home/thanos/chatwootnext-connecta-g0-prep/deploy/e2e/compose.yml`.
- Entrypoint/command efetivos no compose (sem migração/seed/preparação de DB — mesma config já validada):
  - fork-web: `command: ['bundle','exec','rails','s','-b','0.0.0.0','-p','3000']`, `working_dir: /app`.
  - fork-worker: `command: ['bundle','exec','sidekiq','-C','config/sidekiq.yml']`, `working_dir: /app`.
- Nota: `docker image inspect` da imagem mostra `CMD=[irb]` herdado da base; o comando EFETIVO dos containers vem do compose acima (confirmado via `docker inspect <container>` → `CMD=[bundle exec rails ...]` / `[bundle exec sidekiq ...]`). Sem mudança de entrypoint/command neste passo.

## 3. Base / rollback / nova imagem

- Base live verificada: tags `connecta-e2e-fork:local` + `connecta-e2e-fork:20261027-local-coded-layer`, ID `sha256:a9d4a8c733e9c14e65fccdabc060f234d229ab5823eddfd450410d761564b7b5` (igual ao esperado).
- Compatibilidade (host tree × in-container base a9): 8 dos 10 Ruby idênticos; SÓ os 2 fix aprovados divergem (prova de que a base é pré-C.1):
  - tree `socket_hook.rb` `87170f…57bdb` vs base `17f559…c2b8aa6` (cópia pré-C.1 em `/tmp/opencode/fork-layer` = `17f559…`, intocada).
  - tree `admin_metadata_delivery_guard.rb` `9fa191…633b` vs base `c32f2c…581e0c` (cópia pré-C.1 em `/tmp/opencode/fork-layer` = `c32f2c…`, intocada).
- Rollback NOVO preservado: `docker tag connecta-e2e-fork:local connecta-e2e-fork:rollback-2026-10-28-a9d4a8c` → ID `sha256:a9d4a8c733e9c14e65fccdabc060f234d229ab5823eddfd450410d761564b7b5` (igual à base). Rollback anterior `rollback-2026-10-26-c82f2d5` intacto, ID `sha256:c82f2d5330ef89f1b102c521bff324bc8c34811c36f696f4f160fe48c6f8af9e` (não retaggeado, não removido).
- `/tmp/opencode/fork-layer` (baseline primária pré-C.1 do Juiz) NÃO tocada. Novo contexto mínimo: `/tmp/opencode/realtime-dualrole-layer-20261028` com Dockerfile (`FROM <rollback-a9> + WORKDIR /app + COPY exato dos 2 arquivos`) e só os 2 `.rb` aprovados (hashes iguais à tree). Sem specs/context/docs/env/segredos.
- Build local único, sem pull: `docker build --pull=false -t connecta-e2e-fork:local -t connecta-e2e-fork:20261028-dualrole-realtime /tmp/opencode/realtime-dualrole-layer-20261028` → `EXIT=0`.
- Nova imagem: ID `sha256:2d1fe4b7ac78fedbf55ea9a1c36b6e937e6e913ca34d4bd4b0f7fdf528d16455` (ambas tags). USER/ENTRYPOINT/CMD/WORKDIR herdados iguais aos da base (ver §2 sobre comando efetivo via compose).

## 4. SHA dos 10 Ruby (tree = contexto build = dentro de web E worker novos)

- `connecta_scopes_controller.rb` `546d2fbb326f39161b5d9bbaf9d93bd32540f1c49ff6807b26f56d01a4aa869f`
- `runtime/transfer_policy.rb` `45c6e6ae9020a7b57b03ac27c3431d622450d76fe6558649671106b8964a62a7`
- `scope/admin_metadata_delivery_guard.rb` `9fa1915bbadf2a68db32baf5655a5f5bf1ec543a83ca62b4662c19e12da633b0`
- `scope/conversation_http_hook.rb` `911bf1e7acb19c74bf598963b7424a1c5629dfaeb0eb03882ad1afda379f42b0`
- `scope/conversation_query.rb` `d579e7373e30353dea30c4e0a30d00dcebed0f8da2b96553d809baff99fc9331`
- `scope/delivery_check.rb` `fe95dd7238a22bc25395fc892ce296235a1da918152f056dd79d3ca165688262`
- `scope/delivery_context.rb` `928e3b64e75e97f2c482e0473b83403162adfea14ef2e216b5c75b9ffc3e6d09`
- `scope/gate.rb` `3f163d5d71f1efb5277d5c4a07ab48b9eb1b5d5ba8b54b6110b6f39caa99212c`
- `scope/socket_hook.rb` `87170ffdc4ebebf0f229c2fc021acf66ebf117045b9e54aba84c032938d57bdb`
- `scope/native_admin.rb` `a259cbfb65e0a371b8fa473181effa9140142c2bd15b51a8aad7c0e1e8fe5b04`

## 5. Recreate restrito + smoke (somente leitura, sem dados reais)

- Comando: `docker compose -p connecta-e2e -f <compose> up -d --no-deps --force-recreate fork-web fork-worker` → `EXIT=0` (só os 2 serviços; sem up global/down/restart de deps; aviso de orphans ignorado, sem `--remove-orphans`).
- Pós-recreate: web `26b58e6f5f1d` imagem `2d1fe4…` `Up (healthy)`; worker `cc10db30d3ca` imagem `2d1fe4…` `running` `RestartCount=0`. Ambos na MESMA nova imagem.
- Readiness: `docker exec connecta-e2e-fork-web wget -q -O /dev/null http://127.0.0.1:3000/api` → `EXIT=0`.
- Flag runtime (só nome booleano, sem dump): `printenv CONNECTA_HUMAN_NUMBER_ENABLED` = `true` em web E worker.
- Constantes carregadas sem tocar dados/auditoria: `NativeAdmin=Connecta::Scope::NativeAdmin`, `Gate=Connecta::Scope::Gate`, `SocketHook=Connecta::Scope::SocketHook`, `Guard=Connecta::Scope::AdminMetadataDeliveryGuard`; `NativeAdmin.authorized_for?` presente (interface pública real; primeira sonda usou nome errado `authorized_for` e foi corrigida sem invocar nada). Nenhum Gate/DeliveryCheck invocado (não grava auditoria). Nenhuma mensagem real enviada, nenhum token/cookie reutilizado.
- Nota: stderr do runner mostra aviso de collation do Postgres (`chatwoot_e2e`, 2.41 vs 2.36) — só aviso, sem ação (sem ALTER/REFRESH, fora de escopo).

## 6. Invariância (antes → depois)

- Recriados: SOMENTE `connecta-e2e-fork-web` (`a9cbeb800938` → `26b58e6f5f1d`) e `connecta-e2e-fork-worker` (`ea4b0fe40f00` → `cc10db30d3ca`), ambos imagem velha `a9d4a8…` → nova `2d1fe4…`.
- Inalterados (mesmo ID container, mesma imagem, mesmo StartedAt): wp `048682bdd1df` (`e3333b25…`, healthy), wp-admin `176f287883a2` (`7c1766ec…`), baileys-api `70e0bd537c73` (`3b85a133…`, healthy), baileys-redis `1192d11045c1` (`57e4255c…`, healthy), fork-postgres `48afd165c8b4`, fork-redis `e17769424718`, wp-postgres `39b7a37d0cc5`, wp-redis `11c57ecbebc2` (todos RestartCount=0).
- B5: `chatwootnext-rails-1 96bb5c3eea76` (`chatwootnext:local`) `Up 2 days (healthy)` — preservado.
- 3 deploy preexistentes idênticos antes/depois: `deploy/e2e/compose.yml` `7f8ccd…35013`, `deploy/baileys-api/docker-compose.yml` `253173…7436d`, `deploy/e2e/README.md` `7c9c32…0a1cd`. Monorepo `feat/app-solicitacoes` intocado por esta fase (só leitura). Screenshot untracked do monorepo preservado (sem abrir/remover).
- Sem prune/remoção de imagens ou volumes.

## 7. Rollback futuro (DOCUMENTADO — NÃO EXECUTADO)

- Verificação prévia (somente leitura, numa execução futura): `docker image inspect connecta-e2e-fork:rollback-2026-10-28-a9d4a8c --format '{{.Id}}'` deve devolver `sha256:a9d4a8c733e9c14e65fccdabc060f234d229ab5823eddfd450410d761564b7b5`; `docker image inspect connecta-e2e-fork:20261028-dualrole-realtime --format '{{.Id}}'` deve devolver `sha256:2d1fe4b7ac78fedbf55ea9a1c36b6e937e6e913ca34d4bd4b0f7fdf528d16455` (nova imagem preservada — não remover).
- Execução futura válida (exemplo, NÃO EXECUTADO): `docker image tag connecta-e2e-fork:rollback-2026-10-28-a9d4a8c connecta-e2e-fork:local && docker compose -p connecta-e2e -f /home/thanos/chatwootnext-connecta-g0-prep/deploy/e2e/compose.yml up -d --no-deps --force-recreate fork-web fork-worker` (restrito aos 2 serviços; sem editar compose, sem `up` global, sem remover imagens).
- Health após rollback (a fazer se/quando executado — NÃO executado aqui): web `Up (healthy)` via healthcheck `/api` in-container, worker `running` com `RestartCount=0`, demais serviços inalterados.

## 8. Limites

- Smoke de deploy (health/SHA/introspecção de constantes/flag). E2E funcional no browser com WS segue pendente e será feito pelo humano (renovar WS e testar normal após este deploy); nenhuma alegação de E2E browser aqui.
- Sem envio de mensagens reais, sem DB real gravado, sem grants/epochs alterados, sem WP/B5/Baileys tocados, sem `.env` lido/editado, sem segredos/PII neste documento.
- Sugestões de backlog do juiz não abordadas (sem necessidade para este passo); sem polir docs.

## 9. GIT_STATUS_AFTER (sanitizado, sem segredos)

fork `git status --short` (literal, sem commit):
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
?? .context/changelog/CHANGELOG_2026_10_28.md
?? .context/evidence/baileys/2026-10-27-admin-native-local-deploy.md
?? .context/evidence/baileys/2026-10-28-dual-role-realtime-local-deploy.md
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
?? "Captura de tela 2026-10-27 205434.png"
?? apps/whatsapp-platform/.context/changelog/CHANGELOG_2026_10_26.md
?? apps/whatsapp-platform/src/db/repositories/staffAuthEpochRepo.ts
?? apps/whatsapp-platform/src/services/humanService/aclSyncEvents.ts
?? apps/whatsapp-platform/src/services/humanService/aclSyncPublish.ts
?? apps/whatsapp-platform/tests/aclSyncProducers.test.ts
?? apps/whatsapp-platform/tests/aclSyncPublish.test.ts

monorepo `git diff --check`: limpo (exit 0; sem alteração feita aqui).
