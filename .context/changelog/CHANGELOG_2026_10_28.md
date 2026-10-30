# Changelog 2026-10-28

## Fixed (C.1 — precedência nativa+nominal no realtime, sem deploy)
- Causa: `SocketHook#socket_reader?` rejeitava `Projection#admin?` ANTES de considerar o nativo, então usuário que é administrador NATIVO ATUAL da mesma conta E tem grant nominal era excluído do realtime com conteúdo e incluído nos metadados mínimos (`id`, `conversation_id`, `account_id`). O Gate HTTP já priorizava o nativo — por isso envio/persistência funcionavam com refresh.
- `app/services/connecta/scope/socket_hook.rb`: `socket_reader?` agora checa `NativeAdmin.authorized_for?` primeiro e delega ao `Gate#read?` (com auditoria) nos dois ramos; nominal-only continua fora do socket normal (só metadados). `socket_admins` exclui nativo ATUAL da mesma conta da seleção de `AdminMetadataBroadcastJob` (sem duplicidade conteúdo+metadata). `native_tokens_for_account` reconsulta vínculo via `authorized_for?` + `Gate#read?` (`socket_native_admin`, auditado).
- `app/services/connecta/scope/admin_metadata_delivery_guard.rb`: `role_still_allowed?` revalida no delivery — nominal que virou nativo ATUAL da conta não recebe metadata obsoleta enfileirada antes da promoção (revogações/epoch/conta/verificação nominal continuam fail-closed).
- Sem bypass: epoch, conta, roles e auditoria continuam validados dentro do Gate central; `DeliveryCheck` normal inalterado.

## Tests (G0 existente via `--spec --apply`, fixtures sintéticas)
- `spec/connecta/scope_socket_delivery_spec.rb` (+4 dual-role): positivo dual recebe conteúdo pleno (`content`/`sender`) same-account via canal NORMAL sem metadata duplicada; auditoria Gate `allow`; rebaixado/remove vínculo após enqueue não recebe pleno; epoch revogado nega pleno + conta B nunca recebe da conta A.
- Regressão dual primeiro FALHOU no estado atual (`tokens` sem o dual-role) e PASSOU após o fix.
- `spec/connecta/scope_admin_metadata_pending_spec.rb` (+1): nominal promovido a nativo após enqueue não recebe metadata obsoleta neste canal.
- Preservados: nominal-only metadata-only; nativo-only full; multiconta/role removido/downgrade/epoch revogado; `payload legado` fail-closed.
- Combinado: `scope_socket_delivery_spec.rb` + `scope_admin_metadata_pending_spec.rb` + `scope_socket_spec.rb` + `scope_policy_query_spec.rb` = 105 exemplos, 0 falhas.
- `bundle exec rubocop --force-exclusion` nos 4 Ruby tocados: sem ofensas. `git diff --check`: limpo.
- Enterprise: `enterprise/app/listeners/enterprise/action_cable_listener.rb` só trata `copilot_message_created` (broadcast direto ao dono); nenhum overlay toca os módulos C.1.

## Limites / não declarado
- Código + testes C.1 prontos para juiz; deploy NÃO realizado neste passo (fase D separada).
- Nenhum dado real tocado; nenhum perfil/role/grant real alterado; sem frontend/transporte/Baileys; sem credenciais ou PII.

## Deploy D.1 (2026-10-28 — fix C.1 live em fork-web/fork-worker, sem retestar código)

- Base verificada `connecta-e2e-fork:local` = `sha256:a9d4a8c7…` (8/10 Ruby iguais à tree; só os 2 fix C.1 divergiam da base, como esperado). Rollback novo `connecta-e2e-fork:rollback-2026-10-28-a9d4a8c` = mesmo ID da base; rollback `c82f2d5` de 27/10 intacto.
- Build mínimo único (`--pull=false`, sem assets/bundle): `FROM rollback-a9 + COPY` exato dos 2 `.rb` aprovados (`socket_hook.rb 87170f…`, `admin_metadata_delivery_guard.rb 9fa191…`). Nova imagem `connecta-e2e-fork:local` + `connecta-e2e-fork:20261028-dualrole-realtime` = `sha256:2d1fe4b7…`.
- Recreate restrito: `docker compose -p connecta-e2e -f <compose> up -d --no-deps --force-recreate fork-web fork-worker` (exit 0). Web `26b58e6f5f1d` healthy + `wget /api` exit 0; worker `cc10db30d3ca` running RestartCount=0; mesma nova imagem nos dois; SHA dos 10 = tree em ambos; flag `CONNECTA_HUMAN_NUMBER_ENABLED=true` nos dois; constantes `NativeAdmin`/`Gate`/`SocketHook`/`Guard` carregáveis sem tocar dados/auditoria.
- Invariância: demais serviços/DB/WP/B5/Baileys, 3 deploys, monorepo e screenshot preservados (IDs/images/StartedAt/hashes iguais). Sem prune, sem `.env`, sem dados reais.
- Evidência: `.context/evidence/baileys/2026-10-28-dual-role-realtime-local-deploy.md` (comandos, hashes full, health, rollback futuro NÃO executado). Limite: E2E browser/WS fica com o humano.

## Integrado I.1 (F2 lint + S.1 assinatura Baileys + HMAC wire real + marker aviso WP)

### F2 lint (spec authority, sem mudanca de logica)
- `spec/connecta/native_admin_transfer_authority_spec.rb`: 3 consts em bloco RSpec (`CLAIM`/`PLATFORM`/`WIRE_SECRET`) viraram `let` (`claim`/`wire_platform`/`wire_secret`); `let`s agrupados; disable redundante removido. 6 casos/assercoes + HMAC proof preservados. `bundle exec rubocop --force-exclusion` nos 3 arquivos F2: sem ofensas.

### S.1 assinatura (patch aplicado, 8 arquivos, hashes == isolada)
- Patch `/tmp/opencode/baileys-agent-signature-complete-20261028.patch` (SHA `bbe4e5cca358f04d31db38df9e5f7c41fdf335c683895f667c28e67dc9e79505`) aplicado apos `apply --check` limpo (exit 0), sem conflito/3way/restore.
- 8 arquivos: `MessageBuilder.rb` (gate Baileys `channel_whatsapp_signature_enabled`, formato `*Nome*:` igual API, guards bots/relay/private/midia inalterados); `ReplyBox.vue`/`ReplyBottomPanel.vue`/`Editor.vue`/`editorHelper.js` (path nome, toggle WhatsApp real por usuario, sem novo default global); 2 FE new specs + `spec/connecta/baileys_agent_signature_spec.rb` (13 exemplos). Hashes aplicados == isolada (8/8 MATCH).
- Toggle: nome ON/OFF por usuario como API (`channel_whatsapp_signature_enabled` Baileys; `channel_api_signature_enabled` API). Outros providers inalterados.

### HMAC wire real (novo contract, sem mudanca no client)
- Novo `spec/connecta/runtime_platform_client_wire_spec.rb` (1 exemplo): `PlatformClient` REAL contra servidor TCP loopback sintetico (stdlib, sem dependencia/Docker); captura request-target REAL recebido no fio com query em ordem NAO alfabetica (`actor_authority` primeiro) e verifica `X-Connecta-Signature` v1 contra esse canonico exato (timestamp GET path body, segredo sintetico). Sem WebMock como unica prova; sem rede externa; timeouts nativos; ensure fecha socket/thread.
- Resultado: assinatura confere no fio real — sem mismatch real, `platform_client.rb` NAO alterado (WebMock-only normalization nao exigiu fix). Contrato de fio v1 inalterado.

### Auditoria WP notices (gap real, fix minimo)
- Gap: aviso automatico `runtime.ts drainTransferNotices` enviava `{connecta_bot:true}` sem `relay_origin`, que o guard novo `agent_name_prefix_allowed_content?` reconhece — risco de assinar aviso automatico com nome do atendente.
- Fix minimo: payload do aviso passa a `{connecta_bot:true, relay_origin:'bot', connecta_event}` (contrato/mensagem/delivery inalterados). `reception.ts` ja usa `connecta_bot` em todos os envios e nao assina conteudo com nome (fora do escopo I.1; sem alteracao).
- Regressao WP `tests/humanServiceTransferNotice.test.ts`: novo assert `attrs.relay_origin == 'bot'` no aviso pos-ativacao.

### Tests (G0 oficial + Node + FE, todos sinteticos)
- G0 `--spec --apply` (lotes): [wire 1] passou; [authority 6 + assinatura 13 + client-contract 7 = 26] passou; [native-runtime 6 + transaction + hmac 17] passou; [C.1 realtime 105] passou (sem reintroducao dual-role).
- WP: `humanServiceTransferNotice` 4 passou; `tsc --noEmit` limpo.
- FE: arquivos byte-identicos a isolada validada (Vitest 14 novos + regressao 149 passaram / 23 skips preexistentes ja validados em 28; configs byte-identicos); `eslint` 6 arquivos limpo (via deps isolada, sem install/lockfile); `git diff --check` limpo.
- `platform_client.rb` inalterado; B5/deploy/hashes preexistentes preservados; 3 incident paths limpos; sem stash/restore/commit/push/deploy.

### Limites / nao declarado
- Codigo integrado, Gate F pendente; deploy NAO realizado (fase posterior). Sem `.env`/credenciais/PII/dados reais; sem role/grant alterado.

## I.2 doc canônica (2026-10-28 — sem código, pronta Gate F)

- Somente-docs: assinatura Baileys registrada em `.context/architecture.md` (SOMENTE provider baileys USER LATEST `*Nome*:` ON/OFF como API; WABA/Meta inalterados; bot/relay/privado/inbound/vazio excluídos; `relay_origin:'bot'` preserva idempotência); `PROJECT_STATE.md` += I.2 (pronta Gate F, sem deploy); este append.
- Contrato/HMAC/claim e incidente Git vivem no monorepo (ADR-013 + protocolo §9 + evidence `2026-10-28-git-scope-incident.md`); este changelog aponta sem duplicar (1 fato, 1 lugar). "Assinatura" RPC (HMAC) ≠ "assinatura" textual (`*Nome*:`).
- Nenhum código/spec/infra alterado; hashes I.1/F2/S.1 iguais antes/depois; Gate F pendente com todas as frentes; deploy/E2E com o humano.

## Deploy D.1 (2026-10-28 — authority+signature WP+fork com frontend, E2E humano pendente)

- WP: build `apps/whatsapp-platform/Dockerfile` (contexto mono, sem lock/deps change) → candidato `sha256:c25bddb4…` (`transfer.js` com `actor_authority`, `runtime.js` com `relay_origin`) → tag `connecta-e2e-wp:local`; recreate só `wp` (`048682bdd1df` → `e8350b3b448b`, healthy, `/health` 200). Rollback `connecta-e2e-wp:rollback-2026-10-28-e3333b2` = base `e3333b25…`.
- Fork: overlay `FROM rollback-2d1fe4b` + COPY exato de 7 arquivos aprovados (3 Ruby F2/S.1 + 4 frontend assinatura) → `connecta-e2e-fork:local` + `connecta-e2e-fork:20261028-authority-signature` = `sha256:8b3e7584…`; assets compilados via `vite build --mode development` da toolchain pinada (bundle novo `dashboard-CNDfaRmL.js 30f472a7…`, manifest `e6974bfb…`, 235 assets, `usesAgentNameSignature` no bundle); C1/scope + `native_admin.rb` preservados. Recreate só `fork-web` (`26b58e6f5f1d` → `05b5f2fff9f8`, healthy, `/api` 200) + `fork-worker` (`cc10db30d3ca` → `f0825705fc05`, RestartCount=0), mesma imagem. Rollback `connecta-e2e-fork:rollback-2026-10-28-2d1fe4b` = base `2d1fe4b7…`.
- Invariância: demais 14 containers (wp-admin, Baileys x2, 4 DB/Redis e2e, G0 x2, B5 x5) com mesmos IDs/StartedAt/mounts; sem mensagem externa, sem DB mutado; `unclassified` 0 no WP.
- Evidência: `.context/evidence/baileys/2026-10-28-authority-signature-local-deploy.md`. E2E humano (D2) EXPLICITAMENTE PENDENTE; Gate D pendente.

## D3 documentação final (2026-10-28 — somente-docs, D2 pendente, Gate D aguardando juiz)

- Gate F `ses_e7d44629cffenYbu29JpAtmJPi` APPROVED sem required fix; D1 WP+fork local DEPLOYED para TESTE; Gate D aguardando juiz. D2 humano/externo PENDENTE; sem promessa de homologação/produção.
- Modo REAL: `RAILS_ENV=development` + `vite-dev`/`autoBuild=true`, assets `vite build --mode development` (estático, não dev-server); NÃO produção. Rails env base pré-deploy NÃO comprovado (limitação, sem nova inspeção). Divergência método live-temporária + limitação `docker commit` registradas em evidência §8. IDs/full SHAs canônicos em evidência §8 (demais docs só apontam).
- DOCSONLY: nenhum código/spec/config/imagem/runtime/plano alterado; SHAs iguais antes/depois (ver VALIDATION_RUN D3).

## Assinatura Baileys negrito+itálico (código, 2026-10-28 — deploy desta correção PENDENTE)

- Pedido humano: assinatura funcionava como `*Nome*:` mas deve ser negrito+itálico `*_Nome_*:`. Prefixo AUTOMÁTICO Baileys passa a `*_Nome_*:`, FE+BE consistentes; `Channel::Api` e demais providers/formatos inalterados.
- `app/builders/messages/message_builder.rb`: `prepend_agent_name(..., baileys:)` — ramo Baileys extraído (`prepend_baileys_agent_name` + `legacy_same_sender_prefix?` + `normalize_legacy_agent_prefix`) para manter RuboCop limpo; prefixo novo `*_Nome_*:`, idempotente; prefixo LEGADO exato do MESMO sender (`*Nome*:\n`) normalizado UMA vez preservando corpo; `sanitize_agent_name(..., baileys:)` remove também `_` só no nome (corpo intacto); guards bot/`AgentBot`/relay/private/inbound/vazio/mídia-caption inalterados; API default `*Nome*:` intacto.
- FE: `editorHelper.js` `sanitizeAgentName`/`agentNamePrefix`/`prependAgentName` ganham opção `{ baileys }` (default API); `ReplyBox.vue` 3 call sites (`editorSignature`, `isSignatureAvailable`, `applySignatureToMessage`) passam `{ baileys: this.isAWhatsAppBaileysChannel }`; `formattedSignature` retorna `editorSignature` cru (sem mudança); `ReplyBottomPanel.vue`/`Editor.vue` sem mudança (só toggle genérico/preview cru, formato-agnóstico); `composeConversationHelper.js` só usa path API (default intacto).
- Testes: `spec/connecta/baileys_agent_signature_spec.rb` 17 exemplos (ON bold-italic/OFF/API-toggle/provider-negativo/bot/relay/private/inbound/empty/idempotência-new/legacy-normalize-1x/standalone/different-sender/underscore+markup/API regressão ON/OFF); FE `baileysAgentSignature` 13 + `replyBoxBaileysSignature` 7 + `editorHelper.spec.js` 125 (2 novos Baileys, 23 skips pré-existentes). TDD: FE novo falhou ANTES (11F/9P) e passou DEPOIS do fix.
- Validação: G0 oficial `--spec --apply` 17/0; `message_builder_spec` fora da allowlist G0 (não forçado); `bundle exec rubocop --force-exclusion` nos 2 Ruby sem ofensas; `pnpm exec eslint` nos 5 JS/Vue limpo (2 prettier autofix via `--fix`); `git diff --check` limpo. Toolchains do cache (`ruby 3.4.4`, `node 24.19`); `pnpm install --prefer-offline --ignore-scripts` só para deps do lockfile (sem new deps/lockfile). `node` precisou entrar no PATH do runner G0 (script usa `env -i`); sem mudança no script.
- Limites: código pronto p/ juiz (fase código→deploy local); implantação D1 anterior permanece; ESTA correção NÃO implantada (deploy pendente, sem build/restart). Sem dados reais/PII/segredos; histórico DB/mensagens de outros senders intocados.

## Deploy bold-italic 2026-10-28 (fork-web/fork-worker local, assets baked, E2E humano pendente)

- Método sem live edit: stage curado `/tmp/opencode/fork-bold-italic-signature-20261028/` (3 sources + assets), source-candidate `daa86ddd…`, Vite `build --mode development` em container NOVO efêmero `--network none` (exit 0, receita modo dev do stack), imagem FINAL via `docker build` (sem `docker commit`) `sha256:08a33ebf7aefffc3c2ddd33e75e70638cf11bc554a6396b87a595f0d9f0821f3` (`:local` + `:20261028-bold-italic`).
- 3 sources baked == approved FULL: `message_builder.rb 439e114c…`, `editorHelper.js 3042e87d…`, `ReplyBox.vue a0e7a703…`; out-of-scope 7 (Editor/BottomPanel/transfer/controller/native/gate/socket) == base 8b3; env keys 18/18, entrypoint/CMD inalterados.
- Assets baked IN IMAGE e servidos: bundle novo `dashboard-B-6q11C8.js 19600e46…` (HTTP==disco==imagem), manifest `beb7f969…`, 235 arquivos; HTML `/app` 200 aponta bundle novo; old `CNDfaRmL` 404 (esperado).
- Recreate só `fork-web 094cc4c568de` healthy (`/api`+`/app` 200) + `fork-worker cb79d25e873b` RestartCount=0, mesma imagem; WP `e8350b3b448b`/demais 14 intactos (IDs/StartedAt); rollbacks `8b3e758` novo + antigos preservados.
- Formato: Baileys `*_Nome_*:`, API `*Nome*:` intacto. E2E humano NO CELULAR PENDENTE; Gate Runtime pendente. Evidência: `.context/evidence/baileys/2026-10-28-bold-italic-signature-local-deploy.md`.

## Criação em inbox Baileys liberada para autorização nativa (2026-10-28 — código + specs G0, sem deploy)
- Pedido funcional: "todos os usuários podem iniciar conversas" (inclui membros da inbox e admin nativo; não inclui anônimos nem fora da conta/sem inbox). Guard customizado `connecta_scope_create_guard!` REMOVIDO de `app/services/connecta/scope/conversation_http_hook.rb` + linha `prepend_before_action` removida de `app/services/connecta/scope/installer.rb`. Criação em inbox marcada segue a autorização NATIVA (`authorize @inbox, :show?` / `authorize @contact_inbox.inbox, :show?`, `conversations_controller.rb:218-239`, fronteira `Current.account` + `assigned_inboxes`).
- Nenhuma permissão pública, nenhuma allowlist, nenhum bypass de `source_id`; leitura/escrita/transferência inalteradas. Decisão canônica `002` atualizada com seção superseding (proibição 403-total substituída).
- Specs `spec/connecta/scope_http_filter_spec.rb` (bloco criação reescrito, 8 exemplos): agente membro cria via `inbox_id` (payload válido + `assignee_id`, `source_id` dígitos válidos p/ Baileys); admin nativo cria via `source_id`; agente membro via `source_id`; sem-membership 401 sem gravar; outra conta 401/404 sem gravar; `source_id` de outra conta 401 sem gravar; sem token 401 sem gravar; inbox não marcada segue nativa.
- Validação: G0 oficial `--spec --apply spec/connecta/scope_http_filter_spec.rb` = 38 exemplos, 0 falhas (alvo exato `127.0.0.1:55432/conecta_baileys_g0_test` + Redis `127.0.0.1:56379`, dados sintéticos). `git diff --check` limpo.
- Limites: código pronto p/ juiz; NÃO implantado (imagem live `08a33ebf…` ainda contém o bloqueio; deploy/restart pendentes, sem commit). Conversa criada recebe escopo `reception` via `ReceptionScopeCreator`; acesso posterior segue o Gate (não expandido).

## Deploy criação liberada 2026-10-28 (fork-web/fork-worker local, E2E humano pendente)
- Método curado sobre imagem ativa: extração dos 2 Ruby vivos (`docker cp`), verificação byte a byte (worktree = live menos só guard 816B + callback), `ruby -c` OK, `Dockerfile` (`FROM :local` + 2 COPY) em `/tmp/opencode/fork-create-liberation-20261028/`, build `--pull=false` sem segredos. Hashes candidato = publicado: hook `46d99c78…`, installer `8eb80c8d…`; guard ausente (`grep` 0) dentro do web em execução.
- Tags: rollback `connecta-e2e-fork:rollback-2026-10-28-08a33eb` = ID ativo `08a33ebf7aef` (preservado antes); candidata `candidate-20261028-create` = `20261028-conversation-create` = `:local` = `272134b00b24` (full `sha256:272134b0…c`).
- Recriação seletiva WORKTREE: `docker compose -p connecta-e2e -f deploy/e2e/compose.yml up -d --no-deps --force-recreate fork-web fork-worker` (bind LAN `192.168.1.32:3006` preservado; HEAD loopback não usado). Demais serviços intactos (StartedAt inalterados); sem down/volumes/prune/migration.
- Saúde: web `healthy` restarts 0 + `/api` LAN 200; worker `running` restarts 0 oom false; ambos imagem `272134b0…`. Rollbacks antigos intactos; rollback imediato não necessário.
- Prova de criação real NÃO executada (criaria dados reais); E2E humano pendente. Detalhe: `.context/evidence/baileys/2026-10-28-conversation-create-local-deploy.md`.

## Histórico exclusivo de E / S.1 básica — preservado por F3 em 2026-10-29

Fonte deste registro: `.context/changelog/CHANGELOG_2026_10_28.md` do snapshot congelado E `0442d470cb204960b3126d8069ef1c0535036ec9`. Os itens abaixo são relatos históricos de E, **não testes ou operações executados nesta branch em F3**. A implementação vigente é a evolução C negrito-itálico registrada acima; nenhum código S.1 antigo foi reaplicado.

- S.1a backend: E registrou 13 exemplos, com 2 falhas Baileys ON antes do patch e 13 exemplos/0 falhas depois, em alvo sintético G0. Os guards API/Baileys/OFF/outros providers/privada/bots/relay/vazio foram posteriormente incorporados e ampliados em C; este resultado anterior não substitui validação da branch consolidada.
- O runner G0 recusou naquele worktree a execução por propriedade dos containers pertencer ao path original (guarda anti-cross-worktree). E relata execução posterior com as variáveis G0 e `G0TargetGuard.verify!`. F3 não repetiu esse procedimento, não mudou o runner e não autoriza bypass de guarda.
- E referenciou o patch backend isolado `/tmp/opencode/baileys-agent-signature-backend-20261028.patch`; naquela etapa S.1a o frontend, a integração nos originais e o deploy ainda não tinham sido realizados. O caminho é referência histórica, não atestado de existência atual; F3 usou apenas refs congeladas.
- S.1b frontend: E declarou 8 exemplos de helper + 6 de harness (14 novos passando), e regressões `editorHelper.spec` com “123 passed, 23 skipped”, `useUISettings.spec` com 13 e `inboxMixin.spec` com 36. Esses números são preservados como declaração do snapshot E, sem nova medição ou soma. C registra outro resumo de regressão (149 pass/23 skips); não são tratados aqui como contagens reconciliadas ou como homologação atual.
- E também registrou ESLint nos seis arquivos FE sem ocorrências, diff-check limpo e nenhum rerun Ruby/G0 no passo frontend, porque outra frente detinha G0. Deploy/build Docker não foram feitos naquele passo. As etapas posteriores de C acima continuam sendo os registros canônicos de evolução/deploy local, sem atestado de produção desta consolidação.
