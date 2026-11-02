# PROJECT_STATE — chatwootnext

Estado atual: fase, entregas, próximos marcos e pendências. Criado em 2026-10-22.

## Resolução fecha o escopo; reabertura restaura; escrita em resolvida negada — 2026-11-02 (código pronto; build/deploy pendentes)

- Correção 06 do ensaio: conversa resolvida mantinha escopo `active` e o entrante seguinte a reabria. Novo estado terminal legível `closed` (READ, fora de NON_TERMINAL, sem migração); resolver move `reception`/`active`→`closed` (transfer não tocado); entrante após resolver cria conversa nova em `reception` (fluxo nativo com `lock_to_single=false` + `MessageHook` anti-reabertura); reabrir (toggle→open) restaura `active` no mesmo atendimento; escrita em resolvida nega 403 para todos (inclusive admin nativo e bot), só reabertura passa. Tudo sob `CONNECTA_HUMAN_NUMBER_ENABLED` + inbox marcada. Decisão em `.context/decisions/005-resolucao-fecha-escopo-reabertura-restaura.md`; specs em `spec/connecta/scope_conversation_resolution_spec.rb` (12 exemplos, não executados — sem Ruby local, imagem sem gems de teste, specs exigem ambiente F5).
- Pendente nesta frente: build da imagem + backup/rollback, recriar rails/sidekiq, validar (Up, 200, envs, Baileys open), reparo da conversa 2 (`resolved`+`active`→`closed` via rotina nova), changelog.
- Lacuna registrada (sem implementar): ícone/banner "WhatsApp não conectado" na UI.

## Envio em recepção só pelo bot + parked visível — 2026-11-02 ~04:15Z (imagem reception-20261102 ativa no teste; specs novas não executadas)

- Imagem `chatwootnext:teste` = `8026ae16c98b` (`chatwootnext:reception-20261102`); backup `chatwootnext:teste-pre-reception` (=`d539778b0ff0`); rollback = retag + recriar rails/sidekiq. Rails/Sidekiq recriados (Up, health 200, var `CONNECTA_RECEPTION_SENDER_USER_IDS=5` nos dois, inbox 2 Baileys open, logs sem erros).
- Regra: em inbox marcada, recepção libera envio só de `sender_type='User'` com `sender_id` em `CONNECTA_RECEPTION_SENDER_USER_IDS` (checado no SQL pelos campos persistidos, nunca content_attributes); demais remetentes (inclusive admin) seguem parked. Claim parked (scope ausente/reception/transferring) marca a mensagem `failed` com erro em português; manutenção não marca (fluxo 409 preservado). Decisão em `.context/decisions/004-reception-sender-parked-visivel.md`.
- CLAIM_CHECK (só leitura): predicado true para user 5, false para user 2, na conversa 1 (reception). Detalhe em `changelog/CHANGELOG_2026_11_02.md`.
- Pendente: executar `spec/connecta/outbound_dispatch_spec.rb` (+8 exemplos) quando houver ambiente de spec funcional; teste humano do "oi" → menu.

## Correcao 21:36Z — transferir na origem + override persistente (8 grants; sem funcional)

- Grants 6→8 diretos (4/QA): QA3 transfere Farmácia+Hospital lendo só Farmácia; QA4 simétrico. `attendance_outbox` 11→13 `delivered`, heartbeat 21:35:33 `fresh`, TTL120. Override Saude existe no HOST (1601 bytes, placeholders, ignorado `.runtime/`); Chatwoot override com aviso de 3 composes. Serviços `healthy`, restarts 0, sem recriação. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Saude por unidades pronta para teste humano — 2026-11-01 ~21:28Z (candidata ativa, HMAC/ACL/binding/membership; sem teste funcional)

- Saude `wb-saude-backend:latest` = candidata `b8dd0ff5be03` (`f422dcc-compat-src44e261e55953`, `external_number` + `parsePgSafePositiveId`/`parsePgEpoch`); rollbacks `rollback-5d6a159a050f` (=`5d6a159a050f`) + `rollback-aa906eaf735a` preservados. Chatwoot `chatwootnext:teste` `d539778b0ff0`, 187 migrations, coluna presente, inbox2 única conta2.
- HMAC pareado direto nas duas direções em memória (sem troca, sem valor em repo/log): Rails/Sidekiq `HUMAN_NUMBER_ENABLED=true`, `ACCOUNT_ID=2`, `PLATFORM_URL` local, `RECEPTION_ORG_UNIT_ID=ea975324...`, restarts 0. Saude `external_number`, `account2/inbox2/hs_inbox2`, `individual/enforce`, token User2 existente em memória (`AccessToken` 4), número Baileys em memória, `/health`+`/ready` 200.
- Projeção: 3 unidades, 2 vínculos QA 3/4 verificados, 6 grants diretos sem leitura cruzada, heartbeat 4 ciclos (21:21:58→21:27:18), `verified/fresh true`, `admin false`, TTL 120. Binding inbox2 `enforce`, webhook conta2 `.../chatwoot/webhook` (`message_created,conversation_status_changed`), `InboxMember` [2,3,4]. Nenhum atendimento/transferência/protocolo criado pelo agente. Humano testa. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Drift de inbox corrigido (só 20260814120000) — 2026-11-01 ~21:10Z (backup novo válido; inbox API 200; sem restart; sem outras migrations)

- Backup privado novo pré-migração: `.../backups/chatwoot-pre-20260814120000-20261101T210946Z.dump` (506292 bytes, 0600, dir 0700; `pg_restore --list` 1284 entradas, sem restaurar). Backups anteriores preservados.
- Preflight: DB `chatwoot`, imagem ativa `chatwootnext:teste` `d539778b0ff0`, migration file idêntico host/imagem, versão ausente (0), coluna ausente (23 cols), total 186, 29 downs incluindo o alvo. Pós `db:migrate:up VERSION=20260814120000` (rc=0): total 187 (só o alvo), `20261024000001` segue pendente (0), coluna boolean default false NOT NULL, 24 cols, inboxes 1, members 1, downs 29→28.
- API com token existente de User2 só em memória (sem rotação/arquivo/log; `AccessToken` 4→4): `profile` 200 id=2, `account2` 200 id=2, inbox index 200 (1, ids=2, com `prevent_assignment_takeover`), inbox show 200 (id=2, `pat=false`). Detalhe técnico: `User.find(2)` é STI `SuperAdmin` sem `access_tokens`; token lido via `AccessToken.where(owner_id: 2)` dentro do runner.
- Sem restart (Rails/Sidekiq running, restarts 0, mesma imagem; API 200 prova schema recarregado). Health 200; QA 3/4 agents sem inbox; `connecta_*` 10 tabelas todas 0 (sem binding/grant); flags desligadas (transfer ausente, gateway vazio, secret ausente). Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Token User2 validado em memória — 2026-11-01 ~21:05Z (perfil+conta 200; inbox API 500 por drift, não por auth; sem rotação)

- Token existente de User2 (admin conta 2) validado sem expor segredo/PII: `GET /api/v1/profile` 200 (`id==2`), `GET /api/v1/accounts/2` 200 (`id==2`), `token_present=true`, `AccessToken` 4→4 sem mutação. APTO à reutilização em memória na próxima etapa; NÃO escrito no Saúde. Token de usuário (alcance por memberships), não dedicado à conta.
- `GET /api/v1/accounts/2/inboxes/2` e índice → 500 com corpo só `{status,error}`: auth passou, view `_inbox.json.jbuilder:15` (`prevent_assignment_takeover`) quebrou porque o DB do runtime não tem a coluna (23 cols, `has_col=false`), embora `db/schema.rb` tenha. Inbox 2 existe (`Channel::Whatsapp`, 1 membro User2). Integração Saúde segue NÃO configurada.
- Health 200; sem rotação/criação, sem membership/flag/grant/binding, sem restart/migration/build. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Checkpoint Saúde por unidades — 2026-11-01 ~20:50Z (setup parcial; BLOQUEADO com 3 decisões faltantes)

- Backup Saúde válido: `.../backups/saude-pre-humanservice-20261101T204606Z.dump` (0600, `pg_restore --list` 559 entradas, sem restaurar). Backup Chatwoot preservado.
- Base reconciliada: somente `20261024000000`; `20261024000001` redundante (enforcement já existe com default+NOT NULL); 10 tabelas Connecta vazias; QA 3/4 agents sem inbox membership; Rails/Sidekiq sem `CONNECTA_*`, sem restart.
- Criado no municipal: 3 `org_units` (`saude.recepcao` raiz, `saude.farmacia`/`saude.hospital` filhas, todas accepts_cases) + 2 staff sintéticos operator (senha inutilizável). Links 0, grants 0, outbox `acl.sync` 0. Fail-closed intacto.
- B1 LACUNA passo2 (sem fix autorizado): R2 `confirmIdentityLinkAndPublish` aborta (`invalid_acl_sync_chatwoot_user_id`; BIGINT pg vira string); R3 publicaria `false` silencioso. B2: API token atual do Saúde dá 401 na conta 2. B3: boot exige `CHATWOOT_INBOX_IDENTIFIER`, Baileys não tem. Saúde segue em conta1/inbox1, sem `HUMAN_SERVICE_*`.
- Próximo: humano decide (B1) fix de coerção + autorização, (B2) novo token conta 2, (B3) identifier. Só então: HMAC nos dois runtimes, sync/heartbeat, binding, membership por último. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Base local Connecta (modo Saúde por unidades) — 2026-11-01 (migração aditiva aplicada; QA criado sem inbox; enforce DESLIGADO)

- Backup privado pré-migração: `/home/thanos/.local/state/chatwootnext-connecta/backups/chatwoot-pre-20261024000000-20261101T200927Z.dump` (`pg_dump -Fc` do banco `chatwoot`; diretório 0700, arquivo 0600; `pg_restore --list` OK, 1194 entradas; não restaurado). Caminho também em `.../chatwootnext-connecta/LAST_PRE_MIGRATION_BACKUP.path`.
- Migração aplicada: somente `20261024000000` (`db:migrate:up VERSION=20261024000000`, rc=0). Criadas 10 tabelas `connecta_*` (o briefing dizia 11; o arquivo cria 10) e 23 índices/PKs. `gen_random_uuid()` disponível (PG 16). `schema_migrations` 185 → 186. `20261024000001` (add enforcement) continua PENDENTE e não foi aplicada: não rodar `db:migrate` genérico sem decidir sobre ela.
- Agentes QA sintéticos (conta 2, role agent, confirmados, sem super admin): `user_id` 3 e 4, `account_user_id` 3 e 4 (e-mails `*@example.invalid`). Criados sem convite e sem e-mail de confirmação (`skip_confirmation!`). Inbox membership: 0 (única `inbox_members` existente é a do administrador atual, inbox 2, inalterada).
- Efeitos colaterais do callback de criação tratados: (a) `Avatar::AvatarFromGravatarJob` agendado 30 s à frente (HTTP externo ao gravatar.com) removido do Sidekiq antes de rodar, 0 restante; (b) inscrição automática nos canais públicos de chat interno removida para os dois QA (0 restante; canais e membros atuais inalterados). Nenhum job de e-mail/Devise encontrado no Sidekiq nem nos logs.
- Segredos locais (valores nunca impressos): `/home/thanos/.local/state/chatwootnext-connecta/secrets/connecta-hmac.secrets` (campos `CONNECTA_PLATFORM_TO_FORK_SECRET` e `CONNECTA_FORK_TO_PLATFORM_SECRET`, 64 hex cada, gerados agora porque ausentes no env e no `installation_configs`). Credenciais QA em `.../secrets/qa-agents.secrets` (campos `QA_FARMACIA_*` e `QA_HOSPITAL_*`: `_EMAIL`, `_NAME`, `_PASSWORD`). Diretório 0700, arquivos 0600, fora do Git.
- Não aplicado: segredos HMAC ainda não estão no runtime (Rails/Sidekiq sem as variáveis); sem restart; `CONNECTA_TRANSFER_ENABLED` segue false; nenhuma unidade/grant/binding criada.
- Saúde: `/health` HTTP 200 (192.168.1.32:3000); Rails e Sidekiq com `RestartCount` 0 e mesma imagem `d539778b0ff0`.
- Próximo passo (microetapa separada, com autorização): aplicar o par HMAC ao runtime (env das duas apps) e reiniciar só quando autorizado; decidir `20261024000001`; criar unidades/grants e a inbox 2 membership dos QA só quando o enforce/ACL estiverem válidos. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Runtime de teste — 2026-11-01 (imagem nova ATIVA em `:teste`; Rails/Sidekiq no ar; sem migrações)

- `chatwootnext:teste` promovido para `sha256:d539778b0ff0…` (revisão `a661537d4`). Rollback preservado: `chatwootnext:rollback-20261101-236e2c96` = `sha256:236e2c966cb3…`, sem alteração.
- Rails (`/health` HTTP 200 em 192.168.1.32:3000) e Sidekiq em `running`, 0 restarts, mesma imagem. Recriados só `rails` e `sidekiq` com o Compose base + override home, `--no-deps`; override pula `db:chatwoot_prepare` e migrações.
- Postgres, Redis e Baileys-redis iniciados com volumes existentes; Baileys-api `healthy` (Docker healthcheck). Volumes preservados; `schema_migrations` = 185, sem migração nova.
- Gate de transferência (somente leitura): `CONNECTA_TRANSFER_ENABLED` = false; `CONNECTA_GATEWAY_URL` vazio; `CONNECTA_TRANSFER_SECRET` ausente; `CONNECTA_HUMAN_NUMBER_ENABLED` ausente no env do Rails (default false). Nenhuma configuração por conta (`connecta_gateway_url`). Backend municipal: nenhum configurado. Transferência segue desligada e não validada.
- Auth Baileys verificada (2026-11-01, GET somente): 1 inbox Baileys, sem chave própria, usa default key e default URL (`http://baileys-api:3000`); `GET /status/auth` → 200 com a chave efetiva; controles sem chave e com chave inválida → 401. A ressalva anterior de mismatch (chave do container Rails antigo) fica superada pela verificação efetiva. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.
- Não validado: handoff, protocolo, envio de mensagem. Nenhum teste mutante executado. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Build local da main — 2026-11-01 (CONCLUÍDO com teto de 10 GiB; sem deploy; apps paradas)

- Imagem nova `chatwootnext:main-a661537d4-20261101`, ID `sha256:d539778b0ff0…`, revisão `a661537d45961aa678c688d0f6922465e8013c52` (código igual a `03c55d2b9`). Build rc=0 em 2409 s com `--load`.
- Limites do builder `chatwootnext-limited` verificados no cgroup: 2 CPUs (200000/100000), memória 10 GiB, swap extra 0, `--oci-max-parallelism=1`. Cache preservado com `--keep-state`.
- Monitoramento: MemAvailable mínimo ~2,9 GiB (limiar de interrupção 1,5 GiB não atingido); pico do builder ~8,8 GiB; `oom_kill` 0.
- Assets: Vite concluiu em `/app/public/vite`. Ressalva: initializer registrou erro de conexão Postgres durante `assets:precompile`, sem falhar o passo.
- Não ativada: tags `:teste`/`:local` e rollback seguem em `236e2c966cb3`. Apps: 0 running / 67 exited. Builder parado. Nenhum deploy.
- Próxima decisão humana: promover ou não a imagem nova para `:teste`, em autorização separada. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Build local da main — 2026-11-01 (FALHOU por OOM; sem imagem nova; apps paradas)

- Base `main` `a661537d4` (docs sobre `03c55d2b9`; código de build idêntico). Builder dedicado `chatwootnext-limited` com 2 CPUs (`cpu.max` 200000/100000), 6 GiB RAM e swap 0 (verificado no cgroup), `--oci-max-parallelism=1`. Default global intocado.
- `docker buildx build --load` parou em `bundle install -j 4` (Dockerfile:69) com `cannot allocate memory` e `oom_kill 1` após 583 s. Nenhuma imagem `chatwootnext:main-a661537d4-20261101` criada. Tags `:teste`, `:local`, `:rollback-20261101-236e2c96` (ID `236e2c966cb3`) intactas.
- Aplicações: 0 running / 67 exited, nada subido. Builder `chatwootnext-limited0` parado, cache preservado.
- Próxima decisão humana: (A) elevar o limite do builder acima de 6 GiB, ou (B) reduzir `-j 4` no Dockerfile. Nenhuma das duas executada. Detalhe em `changelog/CHANGELOG_2026_11_01.md`.

## Main consolidada — 2026-11-01 (merge fix Baileys 422, sem build/deploy)

- `main` em `03c55d2b9` após fast-forward de `fix/baileys-missing-url-422` sobre `1772a68a3` (13 arquivos, sem perda). Diretório canônico: `/home/thanos/chatwootnext` (branch `main`).
- Worktree temporária `/tmp/opencode/chatwootnext-baileys-422` removida (`git worktree remove`, sem `--force`); branch `fix/baileys-missing-url-422` preservada como referência histórica. `/tmp/opencode/chatwootnext-baileys-runtime` (API Baileys) não tocado.
- Override de teste canônico: `/home/thanos/chatwootnext/docker-compose.teste-lan.baileys-override.yml`. Comando seguro para futuras operações de teste (a partir do diretório canônico):
  `docker compose -f /home/thanos/chatwootnext/docker-compose.teste-lan.yml -f docker-compose.teste-lan.baileys-override.yml up -d rails sidekiq`.
- Ressalvas: labels Compose históricos dos containers de teste ainda apontam para o override no caminho temporário (metadados; nada recriado); código do fix ainda NÃO buildado/ativado no runtime (imagem `chatwootnext:teste` anterior ao fix); docs desta etapa commitadas em commit documental posterior a `03c55d2b9` e publicadas em `origin/main` em 2026-11-01 (autorizado pelo usuário; o push também publica `03c55d2b9`). Detalhe em `.context/changelog/CHANGELOG_2026_11_01.md`.

## Consolidação de produção — 2026-10-29 (F3)

- F2 aceito em `bb4dcce72f8d07e7469cfa9641cf38fce0755c4e`. F3 compara somente os nove SRC de E com C, sem merge/reaplicação de E. Não há hunk funcional E faltante: dois arquivos são duplicados byte a byte em C e seis de código/spec são superados pela evolução negrito-itálico de C.
- Apenas fatos históricos exclusivos do changelog E foram portados, com atribuição explícita e sem declarar seus testes como executados nesta branch. Registro canônico em `changelog/CHANGELOG_2026_10_28.md`; evidências/disposições e mapa dos 17 hunks em `/home/thanos/backups/consolidacao-20261029/p1/fork/f3/`.
- Código, specs, guards de produção e WIP C de F2 permanecem intactos. F4/F5 não iniciados; vetores HMAC/teste realtime preparados pelo coordenador não adicionados por esta etapa.
- Novo pedido humano de entrega: a branch final será `dev` **nos dois repositórios**, criada pelo coordenador somente após os commits finais validados, mantendo `release`. F3 não cria nem troca `dev`; a branch de integração permanece `release/consolidada-producao-20261029`.

## Consolidação de produção — 2026-10-29 (F2)

- F1 aceito em `eacee00fb7892fea73d633382931d3a6c22cb858`. F2 integra somente `refs/consolidacao/20261029/snap/C-wt` (`e36b9f8200f8bf1af467a7f823f96d5d6c7b4df5`), com 62 SRC capturados de C (39 modificados + 23 novos), por merge normal, sem rebase.
- NativeAdmin incluído; admissão manual, `conversation_reuse.rb` e `reception_scope_creator.rb` entram como **WIP não homologado**. ReceptionScopeCreator preserva os bytes do snapshot working tree C, não a versão anterior de HEAD/imagem. Assinatura Baileys `*_Nome_*:` e seus specs incluídos.
- Seis hunks de conflito em cinco arquivos resolvidos por composição; documentos/changelogs unidos. Preservados helpers e escopo do lint F1, CORE/URL/infra de produção e anexos sequenciais de EA no caminho nativo de composição.
- Limitação herdada de C: seletor de setores ainda não conectado ao template do compose; fluxo manual também não encaminha `followUpFiles` separados. Ambos permanecem WIP, não concluídos por F2. Import/ref sem uso removidos apenas para lint, sem esconder arquivo/componente nem inventar integração.
- Evidência desta etapa em `/home/thanos/backups/consolidacao-20261029/p1/fork/f2/`: hashes/diffs dos 62 paths, disposição **provisória** por path, validações focadas e relatório. O ledger definitivo de disposição é do coordenador; os conflitos F2 foram acrescentados ao ledger fork existente.
- Nenhum RSpec, banco, container, produção ou teste completo de F4/F5 executado. Não aplicar preparações F5/HMAC de outros agentes. Próximo passo: aguardar despacho; F3/F4/F5 não iniciados nesta atribuição.

## Consolidação de produção — 2026-10-29 (F1)

- **F1 — integração local por merge normal**, sem bypass dos hooks. O bloqueio inicial de 27 ocorrências foi tratado na continuação autorizada: documentos históricos excluídos estritamente do lint e cinco ocorrências ativas corrigidas sem relaxar regras.
- Branch local `release/consolidada-producao-20261029`, baseada no OID exato de produção `ea9153f2f6d85518dc5d3968c1281dd52fe7206c`, integrando a linha original `beaf180d5b65000f5c4a10dfa15ebe486f7c1b23`, sem rebase. O commit de merge da branch registra os dois pais; OID/evidência externa no relatório final F1.
- Este registro trata do plano de **consolidação**: seu G0 de preservação já foi aprovado. Os registros G0 do plano Baileys abaixo são históricos de outro escopo e não atestam integração final.
- F1 preserva os 5 CORE, URL do gateway por conta e infra de EA. Conflitos resolvidos por hunk, combinando renovação do QR com pareamento por código/alertas de EA e unindo limpeza de listas com revogação Connecta.
- Schema unido à mão, sem aplicação ou regeneração em banco. Todas as migrações mantidas; regeneração e testes Rails completos ficam para F5, com banco sintético e autorização própria.
- Evidências desta etapa e ledger externo em `/home/thanos/backups/consolidacao-20261029/p1/fork/` e `../../ledger/conflitos-fork.tsv` a partir desse diretório. Ver changelog de 2026-10-29.
- Lint mantém os mesmos 152 arquivos ativos e não altera o hook; `.context/evidence/` permanece igual a beaf. Helpers dos controllers passaram por 199 verificações isoladas, incluindo chaves upstream EA e ordem de consultas das flags Connecta. As seis autoformatações do hook preservaram AST de scripts/render.
- Próximo passo: F2 somente após novo despacho. Nenhum snapshot local C/E, push, PR, deploy ou mudança em produção foi aplicado nesta etapa. F1 não equivale à homologação da integração nem aos testes Rails/banco de F5.

## Histórico importado do snapshot C — não atesta execução nesta branch

## Atualização factual — 2026-10-28 (fase DEPLOY bold-italic concluído local, E2E humano + Gate Runtime pendentes — TESTE local, não produção homologada)

- Deploy local concluído (só teste): fork `connecta-e2e-fork:local`/`20261028-bold-italic` `sha256:08a33ebf…` (web `094cc4c568de` healthy `/api`+`/app` 200, worker `cb79d25e873b` RestartCount=0, mesma imagem); recriados SOMENTE fork-web/fork-worker. Rollback novo `rollback-2026-10-28-8b3e758` (= base 8b3) + antigos preservados; WP `e8350b3b448b` e demais 14 intactos.
- Método sem live edit: Vite `build --mode development` em container efêmero `--network none` (exit 0), imagem final via `docker build` com 3 sources + `public/vite-dev` curados (sem `docker commit`, sem segredos). 3 sources baked == approved FULL; bundle novo `dashboard-B-6q11C8.js 19600e46…` servido 200 (SHA==disco==imagem), manifest `beb7f969…`; old `CNDfaRmL` 404 (esperado).
- Formato: Baileys `*_Nome_*:`, API `*Nome*:` intacto. E2E humano NO CELULAR PENDENTE; Gate Runtime (juiz) pendente pós-relatório. Evidência: `.context/evidence/baileys/2026-10-28-bold-italic-signature-local-deploy.md`.

## Atualização factual — 2026-10-28 (fase D.3 documentação final, D2 humano pendente, Gate D aguardando juiz — TESTE local, não produção)

- D3 somente-docs: Gate F `ses_e7d44629cffenYbu29JpAtmJPi` APPROVED sem required fix; D1 WP+fork local DEPLOYED para TESTE; D2 humano/externo PENDENTE; Gate D aguardando juiz. Modo REAL `RAILS_ENV=development` + `vite-dev`/`vite build --mode development` (NÃO produção; Rails env base pré-deploy não comprovado — limitação). Método live-temporário + limitação `docker commit` em evidência §8 (fonte canônica de IDs/full SHAs). DOCSONLY, sem código/runtime/build novo.

## Atualização factual — 2026-10-28 (fase D.1 deploy authority+signature concluído, E2E humano/D2 e Gate D pendentes — TESTE local, não produção homologada)

- Deploy local concluído (só teste): WP `connecta-e2e-wp:local` `c25bddb4…` (container `e8350b3b448b` healthy, `/health` 200) + fork `connecta-e2e-fork:local`/`20261028-authority-signature` `sha256:8b3e7584…` (web `05b5f2fff9f8` healthy `/api` 200, worker `f0825705fc05` RestartCount=0, mesma imagem); recriados SOMENTE wp/fork-web/fork-worker. Rollbacks novos `rollback-2026-10-28-e3333b2` (WP) e `rollback-2026-10-28-2d1fe4b` (fork) preservados; demais 14 serviços (wp-admin, Baileys, DBs, G0, B5) intactos. Bundle frontend novo `dashboard-CNDfaRmL.js` servido 200 com `usesAgentNameSignature`. Evidência: `.context/evidence/baileys/2026-10-28-authority-signature-local-deploy.md`. E2E humano (D2) EXPLICITAMENTE PENDENTE; Gate D pendente; D3 fechamento final posterior.

## Atualização factual — 2026-10-28 (fase D.1 deploy C.1 concluído, E2E browser pendente do humano)

- Deploy local concluído: imagem `connecta-e2e-fork:local` + `connecta-e2e-fork:20261028-dualrole-realtime` `sha256:2d1fe4b7…` (camada mínima dos 2 `.rb` C.1 aprovados sobre rollback-a9 `a9d4a8c7…`); recriados SOMENTE fork-web (`26b58e6f5f1d`, healthy, `wget /api` exit 0) e fork-worker (`cc10db30d3ca`, running, RestartCount=0). SHA dos 10 = tree nos dois; flag `CONNECTA_HUMAN_NUMBER_ENABLED=true` nos dois. Rollback novo `rollback-2026-10-28-a9d4a8c` preservado (= base a9); rollback `c82f2d5` intacto. Demais serviços/DB/WP/B5/Baileys/3 deploys/monorepo/screenshot preservados. Detalhe em `.context/evidence/baileys/2026-10-28-dual-role-realtime-local-deploy.md`. E2E funcional browser/WS pendente (humano).
- Seção abaixo de 2026-10-28 (C.1 pronta para juiz, sem deploy) permanece como registro do passo anterior; o deploy é este passo.

## Atualização factual — 2026-10-28 (fase C.1 realtime dual-role, pronta para juiz, sem deploy)

- Bug real corrigido (sem deploy neste passo): `SocketHook#socket_reader?` rejeitava `Projection#admin?` antes do nativo — dual-role (admin NATIVO ATUAL same-account + grant nominal) ficava fora do realtime com conteúdo e só recebia metadados mínimos de 3 chaves; Gate HTTP já priorizava nativo (envio com refresh funcionava). Detalhe em `.context/changelog/CHANGELOG_2026_10_28.md`.
- Lacuna de teste fechada: nenhum spec anterior combinava `AccountUser administrator` + grant nominal verificado/fresh; regressão nova falhou antes do fix e passou depois (listener REAL → serialize → `ActiveJob::Base.execute`).
- Validação: combinado `scope_socket_delivery` + `scope_admin_metadata_pending` + `scope_socket` + `scope_policy_query` = 105 exemplos, 0 falhas (G0 existente via `--spec --apply`). RuboCop nos 4 Ruby tocados sem ofensas; `git diff --check` limpo; Enterprise sem overlay nos módulos C.1.
- Pronto para juiz C.1; fase D (deploy local) separada e pendente.

## Atualização factual — 2026-10-27 (fase D.1 deploy local concluído)

- Deploy local concluído: imagem `connecta-e2e-fork:local` `a9d4a8c7…` (camada mínima dos 10 .rb aprovados sobre rollback `c82f2d5…`); recriados SOMENTE fork-web (`a9cbeb800938`, healthy) e fork-worker (`ea4b0fe40f00`, running, RestartCount=0). SHA dos 10 dentro dos 2 = tree; NativeAdmin/Gate carregáveis, FeatureFlag=true. wp/B5/Baileys/dados/3 deploy/monorepo intactos. Rollback preservado. Evidência: `.context/evidence/baileys/2026-10-27-admin-native-local-deploy.md`. E2E funcional manual pendente.

## Atualização factual — 2026-10-27 (fase I admin nativo, pronta para juiz)

- Fase I (admin nativo same-account full, conta Chatwoot): código e specs no worktree `feat/connecta-g0-prep`, não commitado. Detalhe completo em `.context/changelog/CHANGELOG_2026_10_27.md` (fonte única; sem recontar história aqui).
- I.1a/I.1b/I.2 + runtime: 3 regressões finais verdes no G0 existente via `--spec --apply` (containment 14, transfer_integration 11, native_admin_runtime_transfer 6, 0 falhas). RuboCop check-only nos 19 Ruby da tarefa sem ofensas; `git diff --check` limpo. Enterprise conferido sem sobreposição realtime/HTTP.
- Nenhum deploy declarado; nenhuma alteração em monorepo, WP, B5, `.env`/segredos ou 3 arquivos deploy preexistentes por esta atribuição.

## Atualização factual — 2026-10-24

- No worktree `feat/connecta-g0-prep`, existe implementação local de produto F3/T4.1/F5 (migração aditiva escrita, runtime opt-in, integração ACL/recepção/transferência, UI e specs escritas). Esta implementação não foi executada nem validada; ver `.context/evidence/baileys/f3-f5-fork.md`.
- G0 R1 foi **REJEITADO**. Código RF1/RF3/RF6 e RF2/RF4/RF5 escrito não equivale a aprovação. Revisão final do Juiz continua pendente.
- O baseline anterior à rodada RF1–RF6 (390 exemplos únicos / 456 execuções) é histórico separado; não representa validação da implementação atual.
- F7/F8 ainda não iniciados neste worktree. Migração, testes, build, servidor, QR, T0.6 e produção continuam pendentes de autorização/liberação aplicável.

## Fase atual
Preparação do G0 do plano Baileys (atendimento em número próprio): G0 **ABERTO**. Preparo local executado em 2026-10-22 (`.context/evidence/g0/01-execucao-preparo-e-validacao.md`); spec T0.1 executada (`.context/evidence/g0/02-inventario-t0-1.md`); runner retomado e repetido sem perda de dados (`.context/evidence/g0/03-retomada-runner.md`). T0.4 (anexos) e T0.5 (AgentBot) medidos em 2026-10-22 (`.context/evidence/g0/05-evid4-anexos.md`, `05-evid6-agentbot.md`): EVID4 e EVID6 têm prova nesta entrega; as demais EVID não. T0.2 parte A (spike de escopo, dois setores na mesma inbox WhatsApp) entregue em 2026-10-22: 30 exemplos verdes pelo runner (`.context/evidence/g0/06-scope-policy-query.md`). T0.2 parte B2 recuperada após timeout do lote (2026-10-22): parcial, com 64 exemplos novos e 160 combinados, 0 falhas; lacunas por área em `.context/evidence/g0/08-recuperacao-b2.md`. T0.2 segue ABERTO (B2 parcial, B3 e superfícies da seção 6 do relatório 07); G0 segue ABERTO. Nenhuma fase de produto iniciada; nenhuma ACL produtiva ou transporte implementado.

## Entregas concluídas
- 2026-10-22: preparo local (não concluído). Correções do Juiz T2 aplicadas e validadas só de forma estática (detalhes no changelog do dia):
  - spec de inventário de rotas `spec/requests/connecta/route_inventory_spec.rb`, com superfícies por área, fronteiras de autenticação, superfícies obrigatórias (incluindo `/cable`, QR/status e o catch-all do SPA);
  - guarda pré-Rails `spec/support/connecta/g0_target_guard.rb`, carregada pelo suporte geral de `rails_helper` e executada só pela spec de inventário;
  - roteiro `scripts/connecta/g0_test_env.sh` (dry-run por padrão; modos `--apply`, `--spec`, `--teardown`) e compose `scripts/connecta/g0-test-services.compose.yml` com autenticação obrigatória.
- 2026-10-22, segunda revisão T2 (REQUIRED_FIXES 1-4, mesmo TASK_ID): fronteiras de autenticação completadas com arquivo:linha; runner checa contexto Docker local antes de qualquer consulta ao daemon e aborta em qualquer modo; recursos do projeto aceitos só por origem Compose (rótulo de projeto e arquivo de configuração); decisões resolvidas registradas. Validado só com docker stub inerte.
- 2026-10-22, retomada do runner (atribuição anterior expirou sem relatório): `--apply` repetido duas vezes no alvo G0, exit 0, sem carga de schema; contêineres, volume, segredo e canário preservados; stub com 29 casos PASS. Detalhes: `.context/evidence/g0/03-retomada-runner.md`.
- 2026-10-22, execução autorizada (citação no briefing do orquestrador): Ruby 3.4.4 no cache da tarefa; `bundle install` (378 gems, lockfile intacto); Postgres e Redis do projeto healthy em 127.0.0.1; banco `conecta_baileys_g0_test` com schema; `route_inventory_spec` com `3 examples, 0 failures` após reclassificar 22 rotas e corrigir o toolchain (ver gotchas). Passos e falhas: `.context/evidence/g0/01-execucao-preparo-e-validacao.md`.
- 2026-10-22, T0.2 parte A (spike, não fecha T0.2): `spec/connecta/scope_policy_query_spec.rb` (30 exemplos, 0 falhas) com gate, query e hooks reais; 7 tabelas `connecta_g0_*` create-only; runner aceita só a lista fixa de extras (`.context/decisions/001-runner-aceita-extras-g0.md`). Núcleo do banco inalterado (hash de schema igual ao baseline). Detalhes: `.context/evidence/g0/06-scope-policy-query.md`.
- 2026-10-22, T0.4 e T0.5 (EVID4 e EVID6, mesma Fase 0): `spec/connecta/attachment_access_spec.rb` (12 exemplos) e `spec/connecta/agent_bot_delivery_spec.rb` (17) passaram pelo launcher G0 com guarda, nas rodadas 4 e 5 (exit 0, 29 exemplos, 0 falhas). Só specs mudaram; nenhum código de app. Detalhes: `.context/evidence/g0/05-evid4-anexos.md` e `05-evid6-agentbot.md`.

- 2026-10-22, T0.2 parte B1 (spike, não fecha T0.2): filtro `POST conversations/filter`, lista e contagens, HTTP de conversa e mensagens (leitura, rascunho, participantes, etiquetas, prioridade, status, agendamento, atribuição), transferência legada negada antes de I/O e criação de conversa negada na inbox marcada. Specs: `scope_http_filter_spec.rb` (34) e `scope_policy_query_spec.rb` (30); combinado com T0.1 e T0.4/T0.5, 96 exemplos, 0 falhas. Pendências: `GET conversations/unread_counts` sem escopo (flag desligada por padrão), B2/B3, T0.3. Detalhes: `.context/evidence/g0/07-scope-http-filter.md`.
- 2026-10-22, recuperação do lote T0.2 B2 após timeout de 1500 s (sem relatório do Coder; nenhum código alterado nesta recuperação): `spec/connecta/scope_related_http_spec.rb` com 64 exemplos, 0 falhas pelo launcher; regressão combinada de 6 specs com 160 exemplos, 0 falhas (2 min 50 s, perto do limite de 180 s). RuboCop em 14 arquivos sem ofensas. B2 parcial: sem caso positivo de admin em integrações e relatórios; criação de contato, chat interno e demais rotas Captain sem cobertura. T0.2 e G0 seguem ABERTOS. Detalhes: `.context/evidence/g0/08-recuperacao-b2.md`.

## Próximos marcos
- Feito com autorização: Ruby 3.4.4 no cache da tarefa; `--apply` (containers); `--spec --apply`. Nada foi instalado globalmente.
- T0.4 e T0.5 medidos (EVID4, EVID6), sem aprovação de gate. Próximos: fechar as lacunas da B2 (lista por área em `.context/evidence/g0/08-recuperacao-b2.md`, seção 3) e a B3 (socket, download de anexos, notificações, exports de conversa, chat interno). `unread_counts` já tem prova na B2, com a flag ligada. T0.3 (corte) e T0.7 (barreira) não iniciados. T0.6 exige autorização para número de teste. T0.1 executado (`.context/evidence/g0/02-inventario-t0-1.md`).

## Decisões resolvidas
Decididas pelo humano em 2026-10-22. Não reabrir sem nova instrução.
1. **Arquivo `.env` na raiz**: a checagem `no_dotenv_in_root` (`scripts/connecta/g0_test_env.sh:80-87`) roda nos modos `prepare` (`:171`) e `--spec` (`:182`), e reprova se existir `.env` ou `.env.*` (exceto `*.example`), porque o Rails o leria. Com `--apply`, a reprovação aborta antes de qualquer comando (`:199-201`); sem `--apply`, aparece como `falta` e o dry-run segue. `--teardown` não executa essa checagem (`:191-195`). Nenhum arquivo é movido ou renomeado pelo código; mover é ação manual, fora deste preparo.
2. **Abrangência da guarda**: só `route_inventory_spec.rb` executa `Connecta::G0TargetGuard.verify!`. `.rspec` e `spec/rails_helper.rb` não mudam. `rails_helper.rb:34` carrega o módulo pelo suporte geral (só define métodos); só a execução é específica do inventário.
3. **Carga da spec fora do alvo**: a guarda aborta o processo (falha alta). Não há skip silencioso.
4. **Redis no G0**: mantido em `127.0.0.1:56379` para provas futuras que usem Redis real. A spec atual não precisa dele: em `Rails.env.test?` o app usa `MockRedis` (`config/initializers/01_redis.rb:10`).
5. **Segredo sintético**: criado no `--apply` em `~/.cache/connecta-g0-test/synthetic-secret` (0600, fora do repo). Não é versionado nem impresso.

## Decisões pendentes
6. **Frontend**: `pnpm install` saiu do preparo. Se alguma spec de request renderizar views com assets Vite, pode ser necessário reinstalar; não verificado.
7. **Runner reexecutável após falha parcial**: implementado em 2026-10-22 (alteração de 15:20Z, antes da retomada; verificada na retomada) pela opção B com prova de posse. Recursos do projeto são reutilizados só com rótulo do projeto e contêiner da origem Compose (`scripts/connecta/g0_test_env.sh:115-132`); segredo não é regenerado com recursos (`:188-191`). Confirmar com o humano: (A) manter essa prova de posse (estado atual, recomendado); (B) voltar à recusa e reexecutar à mão, como na 1ª execução.
8. **Super admin com rotas Devise públicas**: cadastro (`POST /super_admin`), recuperação de senha, confirmação e OAuth/SAML do super admin (`.context/evidence/g0/02-inventario-t0-1.md`, riscos). Opções: (A) request de teste no banco G0, com dados sintéticos, para ver se respondem sem credencial; (B) tratar como achado e corrigir a autenticação em fase própria. Recomendação: A primeiro; B com o dono da autenticação.
9. **`/auth/:provider` sem `redirect_whitelist`**: opções: (A) confirmar que é intencional; (B) configurar a whitelist. Recomendação: confirmar com o dono da autenticação antes de mudar.
10. **Teardown seguido de preparo**: `--teardown --apply` deixa o volume `conecta-baileys-g0-test_g0_postgres` sem contêiner, e o `--apply` seguinte recusa esse volume como órfão (`scripts/connecta/g0_test_env.sh:126-132`). Opções: (A) manter a recusa: para religar, o volume precisa ser removido com autorização, o que apaga o canário e o schema sintéticos; (B) aceitar volume com rótulo do projeto sem contêiner: religa sobre os mesmos dados, com posse menos comprovada. Recomendação: A enquanto o G0 estiver aberto. Não testado no ambiente real (teardown derrubaria os serviços do G0).
11. **Retry de erro genérico do AgentBot (timeout, 404, 5xx fora de 429/500)**: hoje há 1 tentativa e a conversa reabre na hora. O `discard_on` do pai anula o `retry_on` de 5 tentativas (`app/jobs/webhook_job.rb:4-5`; `.context/evidence/g0/05-evid6-agentbot.md`, seção 3). Opções: (A) manter 1 tentativa: erro genérico não gera reenvio; (B) ativar até 5 tentativas: mais entregas concluídas, mas um bot que processou e depois deu timeout recebe o evento de novo, sem deduplicação garantida pelo receptor. Recomendação: A até confirmar que os bots deduplicam pelo `X-Chatwoot-Delivery`. Mudança de app exige autorização.
12. **Acesso a anexos de canal Baileys**: `file_url`, `thumb_url` e `download_url` (`app/models/attachment.rb:57-79`) funcionam só com o link, sem usuário nem conta, e o link de redirect não expira (`.context/evidence/g0/05-evid4-anexos.md`). Opções: (A) manter até a fase de ACL; (B) autorizar por usuário e conta, com epoch que invalida links já emitidos, dentro da T0.2. Recomendação: B, na T0.2, sem mudança nesta fase.

## Pendências e bloqueadores
- **Plano não lido**: a leitura de `/home/thanos/conectacidade/.worktrees/app-solicitacoes/.context/plans/2026-10-22-atendimento-dois-numeros-baileys.md` foi negada. A matriz §10.1 foi usada só pelo resumo do briefing, então a classificação das superfícies é provisória. Responsável: usuário, para liberar a leitura ou validar a classificação.
- **Spec executada**: `3 examples, 0 failures` em 2026-10-22, alvo G0 (`evidence/g0/01` e `02`). A classificação é por área, não a matriz §10.1 literal, que não foi lida.
- **Ruby 3.4.4 só no cache da tarefa** (`~/.cache/connecta-g0-test/toolchain/`). Fora do PATH global; o mise do usuário segue sem versão de `ruby` nesta worktree.
- **Serviços do G0 em execução** (containers healthy; volume `conecta-baileys-g0-test_g0_postgres`). Para parar: `scripts/connecta/g0_test_env.sh --teardown --apply` (mantém volumes; não executado).
- **Origem Compose validada em daemon real**: labels `com.docker.compose.project` e `config_files` conferidos nos containers (`evidence/g0/01`).
- **Lint**: RuboCop nos dois arquivos Ruby do G0, sem ofensas. ESLint não aplicável (sem JS alterado). shellcheck não instalado.
- **Desenho pendente**: specs concorrentes precisam de conexões reais fora da transação externa e limpeza restrita a `conecta_baileys_g0_test`. Não implementado.
- **Canais sem validação de assinatura encontrada no código** (registrado no inventário, sem correção nesta entrega): Twitter/X POST (`app/controllers/api/v1/webhooks_controller.rb:9-15`), Telegram, SMS, Twilio callback/status/voz. Slack uploads não exige usuário e depende só da chave aleatória do blob (`app/controllers/slack_uploads_controller.rb:15-17`).
- **Achados de autenticação não corrigidos**: decisões pendentes 8 e 9. Fora do escopo desta fase.
- **Segredo sintético** em `~/.cache/connecta-g0-test/synthetic-secret` (0600), criado pelo `--apply`; nunca impresso. Remover só em limpeza autorizada.
- **G0 não commitado**: todo o trabalho do G0 segue não rastreado no worktree `feat/connecta-g0-prep`. Nenhum commit foi feito; commit só com pedido explícito.
- **Tempo do launcher**: a regressão combinada de 6 specs leva cerca de 170 s, perto do limite de 180 s. Ver `.context/evidence/g0/08-recuperacao-b2.md`, seção 5.

## Atualização factual — 2026-10-28 (I.1 integração código: F2 lint + S.1 Baileys + HMAC wire + marker WP, sem deploy)

- Assinatura nome ON/OFF por usuário como API (`channel_whatsapp_signature_enabled` Baileys; `channel_api_signature_enabled` API); último humano-overrides plan F.3 old-fallback custom desconsiderado. Código integrado no fork, Gate F pendente, DEPLOY NÃO realizado.
- F2 lint limpo; S.1 8 arquivos aplicados (hashes == isolada); HMAC v1 provado no fio real (loopback, query não-alfabética com claim) sem mudança no client; aviso WP automático com `relay_origin:'bot'` (sem assinatura humana). G0 oficial: wire 1 + authority 6 + assinatura 13 + contract 7 + runtime/transaction/hmac + realtime C.1 105, 0 falhas. Detalhe em `.context/changelog/CHANGELOG_2026_10_28.md`.

## Atualização factual — 2026-10-28 (I.2 documentação canônica: contrato + incidente Git, sem código, pronta Gate F)

- Somente-docs: contrato canônico de autoridade/HMAC em ADR-013 global do monorepo (`docs/adr/013-chatwoot-native-transfer-authority.md`) + adendo §9 do protocolo (`docs/integrations/protocolo-atendimento-humano.md`); incidente Git F1 sanitizado em `.context/evidence/baileys/2026-10-28-git-scope-incident.md` (3 paths CLEAN, stash preservado, sem recovery); assinatura Baileys registrada acima em arquitetura; changelogs 28 atualizados (append). Nenhum código/spec/infra alterado neste passo; código I.1/F2/S.1 intacto; deploy NÃO realizado; Gate F pendente com todas as frentes.

## Consolidação de produção — F4 (2026-10-29)

- Frontend: suite completa com 5 falhas; 3 preexistentes em EA (TransferAction), 2 tratadas (revogação alvo-específica; seletor de teste). Commit `853bbbf59`.
- Backend: sintaxe válida; rubocop e RSpec pendentes por ausência de gems no toolchain (exige autorização para `bundle install`).
- F5/H1 e MessageBuilder fora da allowlist: não executados.
