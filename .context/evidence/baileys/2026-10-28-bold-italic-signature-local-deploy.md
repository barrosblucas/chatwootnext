# Evidência — deploy local bold-italic signature (fork-web/fork-worker, assets baked) — 2026-10-28

Fonte única dos comandos, resultados e limites deste passo de deploy.
Não reimplementa nem retesta código (Gate CÓDIGO juiz `ses_e7ce34bbaffeMiSVbitAQijhx1` = APPROVED, sem required fix); só implanta os 3 sources aprovados em fork-web/fork-worker. Sem SSH remoto/mikromcp, sem envio externo, sem mutação de dados. WP `c25bddb4…` INTACTO.

## 0. Escopo/autorização

- Humano: "faça a implantação da correção do assinatura e deploy" → alvo "Ambiente local connecta-e2e". Ações locais autorizadas: build imagem/assets em candidate efêmero, tags rollback/new, recreate SÓ fork-web/fork-worker, smoke read-only, docs.
- Nova formatação: Baileys `*_Nome_*:` (negrito+itálico); API oficial antiga `*Nome*:` preservada.
- Método MANDATÓRIO cumprido: NENHUM edit no container live. Build Vite em NOVO container CANDIDATO EFÊMERO sem rede; imagem FINAL via `docker build` com contexto mínimo (3 sources + assets curados); NENHUM `docker commit`, NENHUM runtime env herdado, NENHUM segredo.

## 1. Pré-voo (somente leitura)

- `docker context show` = `default`. Compose: `/home/thanos/chatwootnext-connecta-g0-prep/deploy/e2e/compose.yml -p connecta-e2e`.
- Roots: fork `/home/thanos/chatwootnext-connecta-g0-prep` branch `feat/connecta-g0-prep` HEAD `beaf180d5b65000f5c4a10dfa15ebe486f7c1b23`; mono `/home/thanos/conectacidade/.worktrees/app-solicitacoes` branch `feat/app-solicitacoes` HEAD `f5ae41f0c1c3c059620cf6c95eb62167790bc2d5`. Nenhum outro agente; git31-before==after (sources fora do passo intocadas).
- IDs base: fork `:local` = `sha256:8b3e75845024e429fa9feebd82961d6fb6ce19a00174777d36fb5abc495dde38`; WP `:local` = `sha256:c25bddb400ee146fad5e7d66a606157ec88c06dd4fe387f7905f3f2c87363e1d` (confirmado FULL via Docker, prefixos do brief validados).
- Health antes: WP `/health` 200; fork `/api` 200; web healthy worker RestartCount=0.
- 3 sources na BASE 8b3 == versão PREVIOUS implantada (short hashes do brief confirmados FULL): `message_builder.rb dc68a46e…`, `editorHelper.js 13025345…`, `ReplyBox.vue fc9433a9…`. NÃO HEAD (feature bold-italic estava uncommitted, como esperado).
- Árvore nova (approved): `message_builder.rb 439e114c…`, `editorHelper.js 3042e87d…`, `ReplyBox.vue a0e7a703…` (FULL abaixo §7).
- Fora de escopo preservado base==tree: `native_admin.rb a259cbfb…`, `gate.rb 3f163d5d…`, `socket_hook.rb 87170ffd…`, `Editor.vue 3c26b42e…`, `ReplyBottomPanel.vue b2cdd247…`.
- Snapshot StartedAt/IDs/mounts de todos os 17 containers capturado antes (ver §6).

## 2. Rollback (antes de qualquer mutação)

- `docker tag connecta-e2e-fork:local connecta-e2e-fork:rollback-2026-10-28-8b3e758` → `sha256:8b3e75845024e429fa9feebd82961d6fb6ce19a00174777d36fb5abc495dde38` (igual à base; tag nova, não existia; antigas `2d1fe4b`/`e3333b2` intactas, nenhuma imagem/container removido).

## 3. Stage curado (sem live edit)

- Dir: `/tmp/opencode/fork-bold-italic-signature-20261028/` com `Dockerfile.source` (FROM rollback-8b3e758 + COPY 3 fontes + labels revision/feature/stage), `Dockerfile.final` (FROM rollback-8b3e758 + COPY 3 fontes + COPY stage-vite-dev public/vite-dev + labels), `stage/` (3 sources, hashes==tree), `stage-vite-dev/` (output público do build, sem `.env`/secrets/symlinks).

## 4. Build source-candidate + Vite efêmero (prova de não-live)

- `docker build -f Dockerfile.source -t connecta-e2e-fork:source-bold-italic-20261028` → `sha256:daa86dddf314601969aba20c047a4c39b2e8de8732b3a3df487f707aa045ee43`.
- Build assets em container NOVO efêmero SEM rede: `docker run -d --network none --name vite-builder-bolditalic <source-candidate> sleep 600` + `docker exec` com `./node_modules/.bin/vite build --mode development` (binário bakeado da imagem base, `node v24.22.1` da imagem — toolchain base pinada `vite 6.4.2`; receita §8 do D1 anterior). Exit 0 (~55s). SEM `.env`/creds/`--env-file`/mounts de banco/rede app; `RAILS_ENV` default da imagem (development) sem override para production; sem Rails server/entrypoint/migration/DB boot.
- Output copiado PARA FORA: `docker cp vite-builder-bolditalic:/app/public/vite-dev stage-vite-dev` (235 arquivos; builder removido em seguida). Script `sleep` NUNCA executou Rails.
- Assets: bundle novo `dashboard-B-6q11C8.js` (`19600e46…`), manifest `.vite/manifest.json` (`beb7f969…`); conta `usesAgentNameSignature`/`isAWhatsAppBaileysChannel` no bundle (7 refs baileys); old bundle `CNDfaRmL` ausente no contexto; sem symlinks; sem nomes `.env`/secret/credential.

## 5. Imagem final (baked, via build — sem commit)

- `docker build -f Dockerfile.final -t connecta-e2e-fork:candidate-20261028-bolditalic -t connecta-e2e-fork:20261028-bold-italic` → `sha256:08a33ebf7aefffc3c2ddd33e75e70638cf11bc554a6396b87a595f0d9f0821f3`.
- Verificado: 3 sources == tree FULL (§7); out-of-scope 7 arquivos (Editor/BottomPanel + `transfer_transaction.rb 6d175275…` + `connecta_transfers_controller.rb 362da356…` + native_admin/gate/socket) == base 8b3; assets baked IN IMAGE (mesmos SHAs do staging, antes de qualquer run); env key names 18/18 idênticas base vs candidate (só nomes, sem valores); entrypoint/CMD base inalterados (`[]`/`[irb]`, efetivo via compose); assets não carregam API host/chaves.
- Labels: `revision=beaf180d…` (HEAD do repo no build; NÃO alega HEAD conter a feature — feature é dirty aprovada, SHAs fecham em §7) + `connecta.feature=bold-italic-signature-20261028`.

## 6. Publicação + recreate restrito

- `docker tag candidate → connecta-e2e-fork:local` + `:20261028-bold-italic` (ID `08a33ebf…`).
- `docker compose -p connecta-e2e -f <compose> up -d --no-deps --force-recreate fork-web fork-worker` → web `094cc4c568de` healthy + `/api` 200 + `/app` 200; worker `cb79d25e873b` running RestartCount=0; ambos imagem `connecta-e2e-fork:local` (mesmo ID novo).
- Recriados SOMENTE os 2 fork. Invariância (mesmo ID/container/StartedAt): WP `e8350b3b448b` (healthy, `/health` 200, StartedAt `2026-10-28T13:50:33Z`), `wp-admin 176f287883a2`, `baileys-api 70e0bd537c73` (healthy), `baileys-redis 1192d11045c1` (healthy), 4 DB/Redis e2e, G0 x2, B5 x5. Tags antigas/rollback preservadas (lista completa em VALIDATION_RUN do relatório).
- Sem compose down/up geral, prune, volume removal, Git mutations. Sem rollback necessário (health OK de primeira).

## 7. Pós-deploy (provas servidas)

- HTML `/app` (anônimo, sem auth/cookies) referencia bundle NOVO `/vite-dev/assets/dashboard-B-6q11C8.js` (NÃO o antigo `CNDfaRmL`).
- Bundle HTTP 200 SHA == disco == imagem: `19600e46ceb006116b0423aca4dc9a08fc2a17d4a9027e9e9448837e39d103e0`.
- Manifest `.vite/manifest.json`: `beb7f969a2addda2da880c476337135d32013436d21d660d8fd832e18c574ffb` (imagem/disco).
- Chunks amostra resolvem 200: `dashboard-B-6q11C8.js`, `dashboard-CayHQvc3.css`. Old `CNDfaRmL` → 404 (esperado: bundle superado removido pelo build).
- 3 sources live == approved FULL:
  - `message_builder.rb`: `439e114c0883a3a49b0b577b600a094f5bc40e1da8255b5c8439667a948fef84`
  - `editorHelper.js`: `3042e87d567beedb6ebc61a5f4abf32f8d6c1c5b9b091f048db000964b1d5234`
  - `ReplyBox.vue`: `a0e7a703b9ccd36eedb1743b3de6920e86f96e267afb9e596176e89c3c73e17e`
- Formato: Baileys novo `*_Nome_*:`, API `*Nome*:` intacto (prova de código no Gate; aparência NO CELULAR depende de teste humano, ver §8).
- Logs fork (só counts, sem PII/payload): 1 linha `RoutingError GET /vite-dev/assets/dashboard-CNDfaRmL.js` — ruído esperado de browser com cache do bundle antigo após deploy (sem falha funcional; bundle novo 200). Nenhum outro error/exception em 10m.
- Ruby runtime: não invocado além do smoke (sem dados/auditoria tocada). Sem teste de mensagem real/envio/DB/prefs/tokens. Baileys: IDs intactos healthy; `connection=open` NÃO atestado (exigiria endpoint autenticado — fora de escopo), Baileys NÃO reiniciado.
- Modo: `RAILS_ENV=development` + `vite-dev` + `autoBuild=true` (preservado do stack; DEV local, NÃO homolog/prod). `vite build` é build estático, não dev-server.

## 8. E2E humano — EXPLICITAMENTE PENDENTE (D2 manual + Gate Runtime depois)

- Checklist manual (humano, sem disparo automático): (1) hard reload UI; (2) resposta Baileys com assinatura ON mostra `*_Nome_*:` NO CELULAR; (3) assinatura OFF sem prefixo; (4) API segue `*Nome*:`; (5) anúncio bot sem prefixo. Aparência bold+italic NO CELULAR depende do humano — agente NÃO atesta render WhatsApp.
- Gate Runtime (juiz) APÓS este relatório; não chamar juiz/coders desta sessão.

## 9. GIT_STATUS_AFTER (literal; docs deste passo a seguir em CONTEXT_UPDATED)

- `git diff --check` limpo nos 2 roots. Sources funcionais PRE==POST (deploy sem novo SUT edit).
