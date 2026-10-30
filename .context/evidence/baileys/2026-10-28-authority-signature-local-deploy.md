# Evidência D1 — deploy local authority+signature (WP + fork com frontend) — 2026-10-28

Fonte única dos comandos, resultados e limites deste passo de deploy.
Não reimplementa nem retesta código (Gate F APPROVED em passo anterior); só implanta a camada aprovada WP+fork-web+fork-worker. Sem SSH remoto/mikromcp, sem envio externo, sem mutação de dados.

## 0. Escopo/autorização

- Humano: "Faça o deploy para teste" → alvo "Ambiente local connecta-e2e" (WP + fork locais, incluindo interface). Sem servidor remoto/produção, sem custos pagos, sem DB migration, sem mensagem externa.
- Ordem: WP primeiro, depois fork (fork-web + fork-worker). Só os 3 serviços recriados. Nenhum outro restart.
- Adaptação aprovada pelo orquestrador: plano antigo §D1 era Ruby-only (§506-507) e §D3 citava "sem rebuild do frontend" (§549); SUPERADAS — este passo compila e serve o frontend modificado (bundle novo com `usesAgentNameSignature`), não só copia Ruby.

## 1. Pré-voo (somente leitura, antes de qualquer tag/build)

- `docker context show` = `default`.
- Compose canônico ATUAL (não git show HEAD): `/home/thanos/chatwootnext-connecta-g0-prep/deploy/e2e/compose.yml` — serviços `wp`, `wp-admin`, `fork-web`, `fork-worker`, `baileys-redis`, `baileys-api`; imagens `connecta-e2e-wp:local`, `connecta-e2e-wp-admin:local`, `connecta-e2e-fork:local` (web e worker mesma tag).
- Roots absolutos: mono `/home/thanos/conectacidade/.worktrees/app-solicitacoes` branch `feat/app-solicitacoes` HEAD `f5ae41f0c1c3c059620cf6c95eb62167790bc2d5`; fork `/home/thanos/chatwootnext-connecta-g0-prep` branch `feat/connecta-g0-prep` HEAD `beaf180d5b65000f5c4a10dfa15ebe486f7c1b23`.
- IDs base (antes): WP `connecta-e2e-wp:local` = `sha256:e3333b256b88452ed36b85e4ea07729e5a6bbf9261c5862a328bbb93b`; fork `connecta-e2e-fork:local` = `sha256:2d1fe4b7ac78fedbf55ea9a1c36b6e937e6e913ca34d4bd4b0f7fdf528d16455`. Web healthy, worker running RestartCount=0.
- 3 Ruby F2/S1 na IMAGEM base == git show HEAD (base correta, feature só no working tree):
  - `connecta_transfers_controller.rb` base `9d0c4ad9…` == HEAD `9d0c4ad9…`; tree `362da356…` (feature).
  - `transfer_transaction.rb` base `c433bd81…` == HEAD `c433bd81…`; tree `6d175275…` (feature).
  - `message_builder.rb` base `83a62dc7…` == HEAD `83a62dc7…`; tree `dc68a46e…` (feature).
- Health antes: `GET /health` WP 200; `GET /api` fork 200.

## 2. Rollback (ANTES de alterar qualquer tag :local)

- `docker tag connecta-e2e-wp:local connecta-e2e-wp:rollback-2026-10-28-e3333b2` → ID `sha256:e3333b256b…` (igual à base).
- `docker tag connecta-e2e-fork:local connecta-e2e-fork:rollback-2026-10-28-2d1fe4b` → ID `sha256:2d1fe4b7…` (igual à base).
- Nenhuma tag pré-existente com esses nomes (verificado antes); nenhuma tag/imagem removida.

## 3. WP (build + deploy)

- `.dockerignore` raiz mono + `apps/whatsapp-platform/.dockerignore` inspecionados: excluem `.env`/`.env.*` (exceto example), `.git`, `node_modules`, `dist`, screenshots/docs privados; `Dockerfile` só `COPY` manifests, `packages/`, `src/`, `imagens/` — sem segredos/privados no contexto.
- Build: `docker build -f <mono>/apps/whatsapp-platform/Dockerfile -t connecta-e2e-wp:candidate-20261028-authority --label org.opencontainers.image.revision=f5ae41f0… <mono-root>` → ID `sha256:c25bddb400ec…`.
- Conteúdo compilado no candidato: `dist/services/humanService/transfer.js` contém `actor_authority` (count 1, hash `5ab0aa16…` vs base `a2065c10…`); `dist/services/humanService/runtime.js` contém `relay_origin` (count 1, hash `76134bd8…` vs base `1c4d27e0…`). Sem lock/deps change (Dockerfile inalterado, só código-fonte já aprovado).
- Promoção: `docker tag candidate → connecta-e2e-wp:local` (ID `c25bddb4…`).
- Recreate: `docker compose -p connecta-e2e -f <compose> up -d --no-deps --force-recreate --wait wp` → `Healthy`. Container novo `e8350b3b448b` (antes `048682bdd1df`), imagem `connecta-e2e-wp:local`, `GET /health` 200, marcadores live confirmados via `docker exec` grep.

## 4. Fork (overlay 7 arquivos + assets PRODUCTION-vit… development-build compilados via receita existente)

- Fonte da receita: `docker/Dockerfile:74-87` (`pnpm i` + `rake assets:precompile` em production) — adaptada ao runtime REAL deste stack: imagem final roda `RAILS_ENV=development` com `vite-dev` + `autoBuild=true` (confirmado via `rails runner Rails.env` = `development`, `ViteRuby.config.public_output_dir` = `vite-dev`). Produção-`precompile` geraria `vite-production`, que este stack NÃO serve; o build correto é o `vite build --mode development` da toolchain pinada (node `v24.19.0`, `vite 6.4.2` do lockfile, sem nova dep).
- Contexto mínimo em `/tmp/opencode/fork-authority-signature-20261028` (Dockerfile `FROM rollback-2d1fe4b + WORKDIR + COPY` exato de 7 arquivos, labels revision+feature; sem specs/docs/env/segredos):
  - 3 Ruby: `connecta_transfers_controller.rb 362da356…`, `transfer_transaction.rb 6d175275…`, `message_builder.rb dc68a46e…` (iguais à tree).
  - 4 frontend: `editorHelper.js 13025345…` (novo `usesAgentNameSignature`), `ReplyBox.vue fc9433a9…`, `ReplyBottomPanel.vue b2cdd247…`, `Editor.vue 3c26b42e…` (iguais à tree).
- Assets: compilados DENTRO do container live (imagem base, toolchain da imagem, sem acesso DB/Redis runtime, sem creds) via `./node_modules/.bin/vite build --mode development` (exit 0, ~59s), com os 4 fontes novos copiados temporariamente e RESTAURADOS aos originais da base após o build (verificado `editorHelper.js` live == base `9fd35025…`; demais restaurados da base). Bundle novo `dashboard-CNDfaRmL.js` (bundle antigo de 12:37 removido pelo build), manifest novo `.vite/manifest.json` (`e6974bfb…`), 235 arquivos em `assets/`.
- Build overlay: `docker build --pull=false -t connecta-e2e-fork:candidate-20261028-authority -t connecta-e2e-fork:20261028-authority-signature <ctx>` → ID `sha256:8b3e7584…`. Verificado: 7 arquivos == tree (4/4 acima + 3 Ruby); C1/scope + `native_admin.rb` preservados da base (`native_admin a259cbfb…`, `gate 3f163d5d…`, `socket_hook 87170ffd…`).
- Nota de engenharia: `public/vite-dev/` NÃO é baked na imagem (runtime `autoBuild` o gera no primeiro request a partir das fontes da imagem); por isso os assets compilados vivem no volume/overlay do container e o rebuild acontece de novo no recreate a partir das 4 fontes novas da imagem — comportamento validado abaixo.
- Promoção: `docker tag candidate → connecta-e2e-fork:local` (ID `8b3e7584…`).
- Recreate: `up -d --no-deps --force-recreate fork-web fork-worker` → web `05b5f2fff9f8` healthy + `GET /api` 200; worker `f0825705fc05` running RestartCount=0; ambos imagem `connecta-e2e-fork:local` (mesmo ID).

## 5. Pós-deploy (somente leitura, sem dados reais)

- Frontend servido: `GET /app` 200 referencia `/vite-dev/assets/dashboard-CNDfaRmL.js`; `GET` do bundle 200 com SHA igual ao arquivo servido (`30f472a7…`); manifest `e6974bfb…`; bundle contém `usesAgentNameSignature` (count 2); fontes `editorHelper.js` count 1 e `ReplyBox.vue` count 9 na imagem nova.
- WP `/health` 200; fork `/api` 200; web healthy; worker running RestartCount=0 (checks finitos, sem loops).
- Recriados SOMENTE: `connecta-e2e-wp` (`048682bdd1df` → `e8350b3b448b`), `connecta-e2e-fork-web` (`26b58e6f5f1d` → `05b5f2fff9f8`), `connecta-e2e-fork-worker` (`cc10db30d3ca` → `f0825705fc05`).
- Preservados (mesmo ID, mesma imagem, mesmo StartedAt): `connecta-e2e-wp-admin 176f287883a2`, `baileys-api 70e0bd537c73` (healthy), `baileys-redis 1192d11045c1` (healthy), `fork-postgres 48afd165c8b4`, `fork-redis e17769424718`, `wp-postgres 39b7a37d0cc5`, `wp-redis 11c57ecbebc2`, G0 `f0461ddc9f3e`/`bf784eeeb8cb`, B5 `96bb5c3eea76`/`177b744d76a5`/`52bd149b41b5`/`77066f20fd17`/`0c128c655c0a`. Mounts/volumes sem change (nomes/fontes/destinos conferidos no pré-voo).
- WP logs pós-recreate (só contagem por event, sem PII/payload): `service_registered` 13, `server_listening`/`relay_outbox_worker_started`/`muni_maintenance_worker_started`/`muni_maintenance_completed`/`human_service_reconcile_retry`/`chatwoot_inbox_validated` 1 cada; `unclassified` count 0.
- Baileys sessão: endpoint público `/status` (loopback, sem auth) confirma `baileys-api 3.7.3` operacional; detalhe `connection=open` exigiria endpoint autenticado com segredos — NÃO autorizado neste passo; evidência limitada registrada + Baileys IDs intocados (`70e0bd537c73`, `1192d11045c1`, healthy).
- Ruby runtime (nomes/booleanos, sem dados/auditoria invocada): `NativeAdmin`/`Gate` constantes, `NativeAdmin.authorized_for?` presente (`true`).
- Nenhuma mensagem externa enviada; nenhum conteúdo de banco consultado; nenhum role/grant/pref alterado; nenhum teste DB executado.

## 6. E2E humano — EXPLICITAMENTE PENDENTE (D2 posterior)

- Transferência nativa same-account + negativo sem grant + assinatura `*Nome*:` ON/OFF com atesto no celular: NÃO executados aqui (exigem operador humano [H]). D2 posterior.
- Gate D pendente até D2+D3.

## 7. GIT_STATUS_AFTER (literal, sem commit)

- Fork e mono `git diff --check`: limpo nos dois. Fontes funcionais dos dois repos integralmente iguais a antes do deploy (só docs deste passo adicionadas a seguir); SHAs das sources inalteradas pelo deploy (builds só em imagens/containers + `/tmp`).

## 8. D3 DOCUMENTAÇÃO FINAL (2026-10-28 — somente-docs, sem código/runtime/build novo)

- Gate F: juiz `ses_e7d44629cffenYbu29JpAtmJPi` = APPROVED sem required fix (código F2/S.1 + contrato HMAC/nome já implementados; ponteiros: ADR-013 monorepo + protocolo §9 + `.context/architecture.md` assinatura). D1 WP+fork local DEPLOYED para TESTE (este arquivo, fonte canônica). Gate D AGUARDANDO juiz. Todos testes externos/humano D2 PENDENTES; NÃO prometer homologação/produção.
- Modo REAL deste stack (NÃO produção): runtime final `RAILS_ENV=development` com `vite-dev` + `autoBuild=true` (registro D1 §4, via `rails runner Rails.env` = `development`); assets produzidos por `vite build --mode development` (toolchain pinada node `v24.19.0`, `vite 6.4.2`, sem nova dep) e servidos em `/vite-dev/assets/dashboard-CNDfaRmL.js`. `vite build` é build estático, NÃO dev-server. NÃO afirmar `assets build mode production` / `prod precompile`: `precompile` em production geraria `vite-production`, que este stack NÃO serve. Título §4 com truncamento `PRODUCTION-vit… development-build` NÃO é alegação de produção — o modo efetivo é `development`, como registrado acima.
- Decisão orquestrador (escopo humano LOCAL dev): aceito o modo correspondente ao Rails local BASE, sem trocar Rails env/config por conta deste passo; preservado modo/apresentada evidência fiel (headers/asset real); o juiz avaliará a evidência. Estimativa "produção assets" do brief D1 era técnica excessiva frente ao contexto local — superada por esta decisão.
- LIMITAÇÃO Rails env base: registro D1 comprova SOMENTE o runtime final = `development`; Rails env da base ANTES do deploy NÃO comprovado por evidência prévia D1 (sem leitura `.env`/`config.env`; nenhuma inspeção nova executada neste passo DOCSONLY).
- Método / divergência registrada (sem ocultar): os 4 fontes frontend foram copiados TEMPORARIAMENTE para dentro do container live da imagem base, compilados ali (`vite build --mode development`, exit 0, ~59s), e RESTAURADOS aos originais da base após o build (verificado `editorHelper.js` live == base `9fd35025…`; demais restaurados da base). Divergência metodológica vs briefing de contexto isolado (que previa build só em contexto efêmero): operacional, sem perda de dados, sem Git commit inventado. Estado final: 7/7 sources == tree (3 Ruby + 4 frontend) + C1/scope + `native_admin.rb` preservados da base (`native_admin a259cbfb…`, `gate 3f163d5d…`, `socket_hook 87170ffd…`).
- LIMITAÇÃO `docker commit`: registros D1 descrevem build overlay via `docker build --pull=false -t connecta-e2e-fork:candidate-20261028-authority -t connecta-e2e-fork:20261028-authority-signature <ctx /tmp/opencode/fork-authority-signature-20261028>` com `FROM rollback-2d1fe4b + COPY` exato dos 7 arquivos; NENHUM comando `docker commit` nem seus metadados consta nos registros — NÃO afirmar commit parente/metadados. Futuro build deve ocorrer em candidate efêmero antes do recreate; sem novo ADR/plano/tooling por este passo.
- IDs (fonte canônica AQUI; demais docs só apontam, sem duplicar tabelas): WP base `:local` = base/rollback `e3333b256b…` (57 chars como registrado D1 — NÃO full 64, limitação) → novo `sha256:c25bddb400ee146fad5e7d66a606157ec88c06dd4fe387f7905f3f2c87363e1d` (64); fork base/rollback `sha256:2d1fe4b7ac78fedbf55ea9a1c36b6e937e6e913ca34d4bd4b0f7fdf528d16455` (64) → novo `sha256:8b3e75845024e429fa9feebd82961d6fb6ce19a00174777b36fb5abc495dde3f` (64). Rollbacks preservados: `connecta-e2e-wp:rollback-2026-10-28-e3333b2` (= base WP) + `connecta-e2e-fork:rollback-2026-10-28-2d1fe4b` (= base fork). Recriados SOMENTE 3: `connecta-e2e-wp` (`048682bdd1df` → `e8350b3b448b` healthy, `GET /health` 200 ref `192.168.1.32:3005/health`), `connecta-e2e-fork-web` (`26b58e6f5f1d` → `05b5f2fff9f8` healthy, `GET /api` 200) + `connecta-e2e-fork-worker` (`cc10db30d3ca` → `f0825705fc05` running RestartCount=0), mesma imagem nova nos dois fork. Demais 14 com mesmo ID/StartedAt/mounts (snapshot 17 todos da máquina observados, NÃO "14 nesta app"): `wp-admin 176f287883a2`, `baileys-api 70e0bd537c73` (healthy) + `baileys-redis 1192d11045c1` (healthy), 4 DB/Redis e2e, G0 x2, B5 x5.
- Assets/smoke (sem declarar além das provas): `GET /app` 200 referencia `/vite-dev/assets/dashboard-CNDfaRmL.js`; bundle 200 SHA igual ao servido (`30f472a749ece2d5d2c0ca76c771359156f86dabb9048f9070cb4eee272a1f1a`, 64); manifest `.vite/manifest.json` (`e6974bfb26be368fca22331cf6a3c6e4adbb2dc8cb91b8a47891a0173af7f`, 61 chars como registrado — NÃO full, limitação); bundle contém `usesAgentNameSignature` (count 2); HTML/app ref `192.168.1.32:3006`. Baileys: `/status` público confirma `baileys-api 3.7.3` operacional + IDs intactos/healthy; detalhe `connection=open` exigiria endpoint autenticado com segredos — NÃO autorizado/provado. Nenhuma mensagem externa; nenhum DB consultado; nenhum role/grant/pref alterado.
- D2 humano — EXPLICITAMENTE PENDENTE (Gate D depende disto + D3): checklist manual sem disparo automático: (1) hard reload UI (`Ctrl+Shift+R`) carrega bundle novo; (2) admin mesma conta faz transfer Setor A→B; (3) operator sem permissão NÃO consegue; (4) assinatura `*Nome*:` ON/OFF nas respostas Baileys; (5) tempo real C1 sem reload; (6) aviso bot sem assinatura humana. Saúde manual via CELULAR PENDENTE — NÃO executar external message. Assinatura personalizada: regra old plan F3 (custom fallback) SUPERSEDED por NOME API (ADR-013 + protocolo §9); variante custom NÃO requerida para este pedido. NÃO atualizar user prefs.
- DOCSONLY: nenhum código/spec/config/imagem/runtime/plano alterado neste passo; validação em VALIDATION_RUN do relatório D3.
