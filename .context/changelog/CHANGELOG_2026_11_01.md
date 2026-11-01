# Changelog — 2026-11-01

## Merge fix/baileys-missing-url-422 em main (fast-forward, sem build/deploy)

- `main` avançada por fast-forward de `1772a68a3` para `03c55d2b9` (`fix(baileys): validate provider URL and update API deployment`), sem perda: 13 arquivos, 221 inserções, 9 remoções. Conteúdo do fix inalterado (código, specs, locales en/pt_BR/es, manifestos `deploy/baileys-api/`, override de teste, `.context`).
- Checkout canônico: `/home/thanos/chatwootnext`, branch `main`. Worktree temporária `/tmp/opencode/chatwootnext-baileys-422` removida via `git worktree remove` (sem `--force`, limpa e sem bind mounts para o caminho). Branch `fix/baileys-missing-url-422` preservada como referência histórica.
- Override de teste agora canônico em `/home/thanos/chatwootnext/docker-compose.teste-lan.baileys-override.yml`. Próximas operações Compose de teste devem usar os caminhos home:
  `docker compose -f /home/thanos/chatwootnext/docker-compose.teste-lan.yml -f docker-compose.teste-lan.baileys-override.yml up -d rails sidekiq`
  (com `BAILEYS_PROVIDER_DEFAULT_API_KEY` exportada em memória; nunca literal).
- Validação: `git status --short` antes do commit mostrava só os dois docs desta etapa; `git merge-base --is-ancestor fix/baileys-missing-url-422 main` yes; `git diff --check` limpo; caminho temporário ausente; override presente no home; nenhum bind mount para o caminho temporário (0 ocorrências nas inspeções de mount).
- Não executado: `ruby -c` (sem Ruby neste ambiente), `bundle exec rspec`/`rubocop` (sem toolchain Ruby; sem instalar/migrar/provisionar), nenhum build/restart/recriação de container. Código do fix ainda NÃO foi buildado nem ativado no runtime (imagem `chatwootnext:teste` anterior ao fix, conforme changelog de 2026-10-31).
- Riscos/ressalvas: labels Compose históricos dos containers de teste ainda apontam para o override no caminho temporário (somente metadados; nada recriado nesta etapa); documentação desta etapa foi commitada em commit documental posterior a `03c55d2b9` e publicada em `origin/main` (autorização do usuário em 2026-11-01); diretório `/tmp/opencode/chatwootnext-baileys-runtime` (API Baileys) não tocado.

## Build local da main com limites de recurso — falhou por OOM (sem imagem nova)

- Base verificada: `main` em `a661537d4` (commit documental sobre `03c55d2b9`; a diferença é só `.context/`, então o código de build é o de `03c55d2b9`). Árvore limpa, `git diff --check` limpo.
- Builder dedicado `chatwootnext-limited` (driver docker-container, BuildKit v0.33.1, Buildx v0.35.0, Engine 29.6.2, cgroup v2). Não usado como default; default global intocado.
- Limites aplicados e verificados no container `buildx_buildkit_chatwootnext-limited0`: `cpu.max` = 200000/100000 (2 CPUs); `memory.max` = 6442450944 (6 GiB); `memory.swap.max` = 0 (swap total = 6 GiB). BuildKit com `--oci-max-parallelism=1`, via flag do builder (sem arquivo de config no repo).
- Build `docker buildx build --builder chatwootnext-limited --load -f docker/Dockerfile` falhou em 583 s no passo `pre-builder 12/19` (`bundle install -j 4 -r 3`, Dockerfile:69): `cannot allocate memory`; cgroup do builder registrou `oom_kill 1`. Sem imagem `chatwootnext:main-a661537d4-20261101`. Log sanitizado: `/tmp/opencode/chatwootnext-build-20261101.log`.
- Imagens antigas intactas (`:teste`, `:local`, `:rollback-20261101-236e2c96`, ID `236e2c966cb3`). Nenhuma remoção, prune ou alteração de cache/volume.
- Aplicações: 0 running, 67 exited (sem alteração); o builder ficou parado (`docker stop`, cache preservado) após a falha.
- Não executado: validação de assets, sintaxe Ruby em container e qualquer subida de Rails/Sidekiq/Baileys/DB.
- Próxima decisão (não executada): aumentar o limite do builder acima de 6 GiB, ou reduzir a concorrência do `bundle install` no Dockerfile (`-j 4`) — ambas exigem autorização, pois a primeira altera orçamento de recurso e a segunda muda o Dockerfile.

## Build local da main com teto de 10 GiB — concluído, sem deploy

- Autorização humana: aumento do teto do builder de 6 GiB para 10 GiB. Build de `a661537d4` (código igual a `03c55d2b9`) com 2 CPUs, sem swap adicional.
- Builder `chatwootnext-limited` recriado com `--keep-state` (volume `buildx_buildkit_chatwootnext-limited0_state` reutilizado, cache preservado). Limites verificados no cgroup: `cpu.max` 200000/100000; `memory.max` 10737418240 (10 GiB); `memory.swap.max` 0 (memória+swap = 10 GiB, sem swap extra); `--oci-max-parallelism=1`. Default global intocado; Dockerfile sem alteração.
- Build `docker buildx build --builder chatwootnext-limited --load --progress plain` concluiu com rc=0 em 2409 s (~40 min). Log sanitizado: `/tmp/opencode/chatwootnext-build-20261101-10g.log`.
- Imagem nova: `chatwootnext:main-a661537d4-20261101`, ID `sha256:d539778b0ff0…`, 714 MB, label `org.opencontainers.image.revision=a661537d45961aa678c688d0f6922465e8013c52` conferido. Assets: `assets:precompile` concluiu, Vite `built in 1m 9s`, `Build with Vite complete: /app/public/vite`.
- Ressalva do build: durante `assets:precompile` um initializer registrou `Failed to configure AI Agents SDK: connection ... port 5432 refused` (sem Postgres no build); o passo terminou com sucesso. Não investigado nesta etapa; registrar em gotchas se reaparecer em runtime.
- Monitoramento (amostras de 5 s, `/tmp/opencode/build-monitor-20261101.log`, 15:56:10–16:36:14): MemAvailable mínimo 3046944 kB (~2,9 GiB), acima do limiar de interrupção de 1,5 GiB; PSI full avg10 máximo ~0,3 (sem pressão séria); pico do cgroup do builder 9426927616 B (~8,8 GiB) dentro do teto; `oom_kill` 0. Interrupção não foi disparada. Ressalva: o monitor não gravou linha de resumo ao final; os valores acima foram extraídos das amostras.
- Memória ao fim: MemAvailable 11501644 kB; SwapFree 3466136 kB; disco livre 117G em `/`.
- Imagens antigas intactas (`:teste`, `:local`, `:rollback-20261101-236e2c96`, `236e2c966cb3`). Nenhuma remoção, prune ou alteração de volumes.
- Aplicações: 0 running, 67 exited (sem alteração). Builder parado com `docker stop` ao final, cache preservado.
- Sem deploy, sem subida de Rails/Sidekiq/Baileys/DB, sem testes de DB. Imagem nova ainda NÃO está ativa no runtime: `:teste`/`:local` continuam apontando para a imagem anterior. Próxima etapa (não executada): decidir se a imagem nova substitui o `:teste` em nova autorização.

## Runtime de teste com imagem nova — Rails/Sidekiq no ar (sem migrações)

- Promoção: `chatwootnext:main-a661537d4-20261101` (`sha256:d539778b0ff0…`, revisão `a661537d4`) tagueada como `chatwootnext:teste`. Rollback `chatwootnext:rollback-20261101-236e2c96` (`sha256:236e2c966cb3…`) preservado.
- Dependências iniciadas com containers e volumes existentes: `chatwootnext-postgres-1` (pg_isready ok), `chatwootnext-redis-1` (PONG autenticado), `chatwootnext-baileys-teste-redis-1` (healthy), `chatwootnext-baileys-teste-baileys-api-1` (healthy pelo healthcheck do Docker; porta host 127.0.0.1:3025 respondeu 404 na raiz, sem consulta de conteúdo).
- Deploy: `docker compose -f docker-compose.teste-lan.yml -f docker-compose.teste-lan.baileys-override.yml up -d --no-deps rails sidekiq` (override em `/home/thanos/chatwootnext`, não no caminho temporário antigo). Labels de projeto de rails/sidekiq agora apontam para o override home.
- Verificação: rails e sidekiq `running`, restarts 0, imagem `d539778b0ff0`, label de revisão `a661537d4`. `GET http://192.168.1.32:3000/health` → 200. Log do Rails com `Skipping db:chatwoot_prepare (test override, no migrations)`. `schema_migrations` = 185, sem migração nova.
- Gate de transferência, leitura por SQL em `READ ONLY`, sem alterar: `CONNECTA_TRANSFER_ENABLED` = false; `CONNECTA_GATEWAY_URL` vazio; `CONNECTA_TRANSFER_SECRET` ausente (valor não lido); `CONNECTA_HUMAN_NUMBER_ENABLED` ausente no env do Rails (default false); sem `connecta_gateway_url` em contas (2 contas). Backend municipal: nenhum configurado.
- Ressalva de auth (não corrigida): hash da `BAILEYS_PROVIDER_DEFAULT_API_KEY` recuperada do container Rails anterior difere do hash de `BAILEYS_API_KEY` do Baileys-api. Chave não alterada. Consequência provável: chamadas Rails→Baileys com 401 até decisão humana sobre qual chave manter.
- Não validado: integração, transferência, protocolo, envio de mensagem. Nenhum teste mutante. Nenhum `.env` lido por este trabalho (chave recuperada de env de container em memória).
- Pendente: decisão humana sobre a chave Baileys; habilitar flags ou configurar gateway exige autorização separada.

## Verificação de autenticação Baileys por inbox (somente GET, sem mutação)

- Precedência usada pelo código (`whatsapp_baileys_service.rb:758-760`, `:735-736`): `provider_config['api_key']` da inbox, senão `BAILEYS_PROVIDER_DEFAULT_API_KEY`; URL: `provider_config['provider_url']`, senão `BAILEYS_PROVIDER_DEFAULT_URL`.
- Inboxes Baileys (`Channel::Whatsapp` com provider `baileys`): 1. Sem chave própria, usa default key e default URL (`http://baileys-api:3000`).
- Execução: `bin/rails runner` no `chatwootnext-rails-1`, script em `/tmp/opencode/baileys_auth_check.rb`, chave só em memória. Sem save, update ou POST. Mensagens, contatos e conversas não lidos.
- Resultado: `GET /status` → 200; `GET /status/auth` com a chave efetiva → 200.
- Controles (GET, host `127.0.0.1:3025`): `/status/auth` sem chave → 401; com chave inválida → 401. Prova que o header é exigido e a chave efetiva é aceita.
- Conclusão: auth efetiva OK. A ressalva de mismatch do deploy anterior (chave do container Rails antigo) fica superada. Nenhuma correção necessária.
- Rails `/health` 200 e 6 containers do Chatwootnext ativos após a verificação. Nada reiniciado, recriado ou alterado.
- Pendente (não aplicado): configuração de transferência (CONNECTA_TRANSFER_ENABLED, gateway, secret), após os endpoints municipais estarem prontos.

## Base local Connecta: backup, migração aditiva, QA sem inbox e par HMAC (modo Saúde por unidades; enforce desligado)

Escopo: somente `/home/thanos/chatwootnext` (banco local `chatwoot`). Sem produção, sem restart, sem commit. A seção "Runtime de teste" acima (sem migrações) vale até este passo; a partir daqui `schema_migrations` tem `20261024000000`.

### Backup privado (antes de qualquer mudança)
- `pg_dump -Fc --no-owner --no-acl` do banco `chatwoot` via `chatwootnext-postgres-1`, stream para arquivo. Caminho: `/home/thanos/.local/state/chatwootnext-connecta/backups/chatwoot-pre-20261024000000-20261101T200927Z.dump` (476446 bytes; 0700 diretório, 0600 arquivo). Validação: `pg_restore --list` com 1194 entradas, sem restaurar nem ler dados. Nenhum backup antigo foi tocado.

### Preflight
- DB real `chatwoot` (Rails `production`, host `postgres`). PG 16.14; `pgcrypto` 1.3 instalada; `gen_random_uuid` disponível. Migração `20261024000000` presente na imagem `d539778b0ff0` com o mesmo SHA-256 do arquivo local (`8fb909f7…`). Versão não aplicada; nenhuma tabela `connecta_*` existia; `schema_migrations` máx. `20260718000000`, total 185.
- Conta 2 (`Prefeitura Municipal de Bandeirantes`): inbox 2 (Baileys) é a única; `account_users` 2 (usuário 1 admin da conta 1; usuário 2 admin da conta 2). Inbox members antes: 1 (usuário 2 na inbox 2).
- Callbacks auditados: `AccountUser after_create_commit` → `AGENT_ADDED` (sem consumidor em `app/listeners`, `lib`, `enterprise`), `create_notification_setting` (interno), `add_to_public_internal_chat_channels` (interno, canal público da conta 2). `User`: Devise `confirmable` sem e-mail quando `confirmed_at` definido; `Avatarable` → `Avatar::AvatarFromGravatarJob` (wait 30 s, HTTP externo `gravatar.com` com o hash do e-mail; `DISABLE_GRAVATAR` não existe no `installation_configs`). Plano `enterprise` (sem limite de usuários premium).

### Migração
- `bin/rails db:migrate:up VERSION=20261024000000` no `chatwootnext-rails-1` (rc=0). Nenhum outro `migrate`/`prepare`/`seed`.
- Pós: 10 tabelas `connecta_*` (access_audits, acl_sync_state, conversation_scopes, org_units, outbound_dispatches, outbox, scoped_inboxes, transfers, user_auth_epochs, user_grants), 23 índices/PKs, sem linhas, `schema_migrations` 186 com `20261024000000` (e nada além). ATENÇÃO: o briefing falava em 11 tabelas; o arquivo cria 10 (contagem de `create_table`). Sem DML.
- `20261024000001_add_enforcement_to_connecta_scoped_inboxes.rb` continua PENDENTE (não aplicada, fora do escopo). Um `db:migrate` genérico ou `db:chatwoot_prepare` a aplicaria; não executar sem decisão.

### QA sintético (conta 2)
- Criados 2 usuários com `user_id` 3 e 4 e `account_user_id` 3 e 4: `role=agent`, `account_id=2`, `confirmed=true`, sem registro em `SuperAdmin`. E-mails sintéticos `*@example.invalid`; nomes "QA Farmacia Sintetico" e "QA Hospital Sintetico". Script em `/tmp/opencode/connecta-qa/qa_setup.rb` (copiado para o container e removido depois); senha recebida via stdin, nunca em argv nem na saída.
- Membership em inbox: 0 para QA (`inbox_members` continua 1: usuário 2 na inbox 2, inalterado). Usuários existentes não foram alterados (o `updated_at` do usuário 2 e do account_user 2 às 20:09:50Z é da própria sessão de UI do administrador, `PUT /api/v1/profile`, não deste passo).
- Efeitos do callback tratados: o Gravatar agendado para cada QA foi removido do `Sidekiq::ScheduledSet` no mesmo processo, antes de executar (0 restantes); a inscrição automática nos canais públicos de chat interno foi removida para os dois QA (0 restantes; os 2 membros de canal existentes continuam). Nenhum job de e-mail nem `AvatarFromUrlJob` apareceu no Sidekiq/logs (contagem zero desde 20:09).
- Credenciais QA (senhas): `/home/thanos/.local/state/chatwootnext-connecta/secrets/qa-agents.secrets`, 0600, campos `QA_FARMACIA_EMAIL`, `QA_FARMACIA_NAME`, `QA_FARMACIA_PASSWORD`, `QA_HOSPITAL_EMAIL`, `QA_HOSPITAL_NAME`, `QA_HOSPITAL_PASSWORD`. Fora do repo e do `.context`.

### Segredos HMAC (par fork/plataforma)
- Ausentes no env do Rails/Sidekiq e no `installation_configs`. Gerados agora com `openssl rand -hex 32` (64 caracteres cada): `/home/thanos/.local/state/chatwootnext-connecta/secrets/connecta-hmac.secrets` (0600), campos `CONNECTA_PLATFORM_TO_FORK_SECRET` e `CONNECTA_FORK_TO_PLATFORM_SECRET`. Não aplicados ao runtime (ainda) e não alterados nenhum outro segredo (`CONNECTA_TRANSFER_SECRET` continua ausente).

### Validação
- `docker inspect`: Rails e Sidekiq `RestartCount=0`, iniciados às 17:02Z; mesma imagem `d539778b0ff0`. `curl http://192.168.1.32:3000/health` → 200.
- `git diff --check`: sem saída (ver relatório).

### Pendente
- Aplicar o par HMAC ao runtime (env da Rails/Sidekiq) e reiniciar só com autorização separada.
- Decidir `20261024000001`.
- Inbox membership dos QA e unidades/grants: só quando o enforce/ACL estiverem válidos (ver PROJECT_STATE).

## Checkpoint Saúde por unidades — 2026-11-01 ~20:50Z (BACKUP Saúde OK; base reconciliada; setup parcial BLOQUEADO por lacuna passo2 + token + identifier)

Escopo: somente leitura/configuração local autorizada. Sem produção, sem commit, sem testes funcionais, nenhum POST de negócio.

### Reconciliação da base (divergência briefing × PROJECT_STATE resolvida a favor do briefing)
- `schema_migrations`: `20261024000000` aplicada (1), `20261024000001` ausente (0). `20261024000001` é redundante nesta base: `20261024000000` já cria `connecta_scoped_inboxes.enforcement` (`default enforce`, NOT NULL) e a coluna existe (`column_exists?` true). Nenhuma migration executada.
- `connecta_*`: 10 tabelas, 0 unidades, 0 grants, 0 bindings. QA Farmácia (user 3, account_user 3, agent) e QA Hospital (user 4, account_user 4, agent) confirmados, sem `InboxMember` na inbox 2 (só o admin atual). Conta 2 + inbox 2 Baileys única.
- Segredos (só nomes/formatos, nunca valores): `connecta-hmac.secrets` com `CONNECTA_PLATFORM_TO_FORK_SECRET` e `CONNECTA_FORK_TO_PLATFORM_SECRET` (64 chars cada); `qa-agents.secrets` com os 6 campos QA; tudo 0600 em diretórios 0700. Backup Chatwoot pré-migração preservado e não lido.

### Backup municipal Saúde (novo, válido, privado)
- `pg_dump -Fc --no-owner --no-acl` do banco `whatsapp_bot` via `wb-db-saude`: `/home/thanos/.local/state/chatwootnext-connecta/backups/saude-pre-humanservice-20261101T204606Z.dump` (238551 bytes, 0600). Validação sem restaurar nem ler dados: `file` = PostgreSQL custom dump, `pg_restore --list` no container = 559 entradas.

### Saúde: unidades + staff criados; vínculos/grants BLOQUEADOS por lacuna real
- Criados idempotentemente no banco municipal (script Node no `wb-saude-backend` via `dist`, sem segredos no log): 3 `org_units` (`saude.recepcao` raiz accepts_cases, `saude.farmacia` + `saude.hospital` filhas accepts_cases) e 2 `staff_users` sintéticos role operator com senha inutilizável. Contagens finais: units 3, staff 2, links ativos 0, grants ativos 0, outbox `acl.sync` pendente 0. Código órfão de vínculo removido (0 restante).
- LACUNA (sem correção — fora de autorização para novo desenvolvimento): `confirmIdentityLinkAndPublish` (R2) aborta com `invalid_acl_sync_chatwoot_user_id` contra DB real porque `node-pg` devolve BIGINT (`chatwoot_user_id`) como string e `assertSafePositiveInt` rejeita (`aclSyncEvents.ts:85`, `aclSyncPublish.ts:111`). ROLLBACK total (nada parcial). Pior: R3 (`grantAndPublish`) com `epoch` BIGINT-string cai em `published:false` silencioso (`aclSyncPublish.ts:152-153`), grant persistiria sem nunca publicar. Evidência: `SETUP_FAIL invalid_acl_sync_chatwoot_user_id` do script `/tmp/opencode/saude-units-setup.js` (host, sem segredos; reutilizável após o fix).
- Fail-closed preservado: nada projetado no Chatwoot (0/0/0), nenhum membership, nenhum binding, flags desligadas, HMAC ainda não aplicado, nenhum restart. Rails/Sidekiq sem nenhuma var `CONNECTA_*` (só Baileys defaults).

### Bloqueadores adicionais medidos (sem valores expostos)
- B2: `CHATWOOT_API_ACCESS_TOKEN` atual do backend Saúde retorna 401 em `/api/v1/accounts/2`, `/api/v1/accounts/1` e `/api/v1/profile` (base URL = LAN Chatwoot, `/health` 200). Nenhum token válido para a conta 2; criar novo token é decisão humana.
- B3: `config.ts:58-59` exige `CHATWOOT_INBOX_IDENTIFIER` no boot com provider chatwoot, mas inbox 2 Baileys não tem identifier (nem `Inbox` nem `Channel::Whatsapp` têm a coluna; endpoints públicos `/public/api/v1/inboxes/{id}` resolvem só `Channel::Api`). Usar número como identifier seria inventar mapeamento: reportado, não aplicado.
- Saúde ainda aponta para conta 1/inbox 1 (`CHATWOOT_ACCOUNT_ID=1`, `CHATWOOT_INBOX_ID=1`, sem `HUMAN_SERVICE_*`/`CONNECTA_*`/`ATTENDANCE_ADMISSION_MODE`/`STAFF_AUTH_MODE`). Não alterado.
- Validação técnica: `GET /health` 200 (Rails LAN, Saúde LAN, Gateway) + `/ready` 200 Saúde (`numberMode: dedicated`); `git diff --check` limpo. Nenhum teste funcional ou envio real.

## Validação do token existente de User2 (somente GET, sem rotação; inbox 500 por coluna ausente, não por auth) — 2026-11-01 ~21:05Z

- Escopo: somente leitura técnica no runtime Chatwootnext; token recuperado em memória de processo via `User.find(2).access_token` (campo `token`), sem imprimir/gravar/retornar valor ou hash, sem argv/arquivo novo, sem `reset/regenerate/create`. Nenhum `.env` lido; nenhum host externo consultado.
- Execução: `bin/rails runner` no `chatwootnext-rails-1` (scripts em `/tmp`, removidos após uso), `Net::HTTP` com timeout 10 s contra `127.0.0.1:3000` com header `api_access_token`. Somente GETs; payloads PII descartados (checados só IDs técnicos).
- Resultado: `GET /api/v1/profile` → 200 com `id==2` true; `GET /api/v1/accounts/2` → 200 com `id==2` true; `token_present=true`; `AccessToken` 4 antes/depois (`no_token_mutation=true`). `GET /api/v1/accounts/2/inboxes/2` e `GET /api/v1/accounts/2/inboxes` → 500 com corpo só `{status,error}` (sem PII impressa).
- Causa do 500 (verificável, não é auth): controller processou (`Processing by Api::V1::Accounts::InboxesController#show/index`) e a view falhou com `ActionView::Template::Error (undefined method 'prevent_assignment_takeover' for Inbox)` / `NoMethodError`. `app/views/api/v1/models/_inbox.json.jbuilder:15` chama `resource.prevent_assignment_takeover`; `db/schema.rb` tem a coluna, mas o DB do runtime não (`Inbox.column_names.include?` false, 23 colunas; `schema_migrations` máx `20261024000000`; volume antigo sem `db:chatwoot_prepare`). Ou seja: auth passou, o render quebrou por drift código×DB.
- Conclusão: token existente de User2 APTO à reutilização em memória na próxima etapa (perfil+conta 200 provam autenticação e membership conta 2); NÃO escrito no backend Saúde nesta frente. Token de usuário (alcance segue memberships), não account-scoped dedicado. Inbox 2 existe (`Inbox id 2 account 2`, `Channel::Whatsapp`, 1 membro = User2, Baileys única na conta 2), mas seu metadata via API segue 500 até o drift ser tratado em frente própria.
- Preservado: `/health` 200; nenhuma rotação/criação de credencial, nenhuma membership/flag/grant/binding alterada, nenhum restart/build/migration; QA sem inbox intacto. Integração Saúde NÃO configurada e NÃO declarada concluída.

## Drift de inbox corrigido (somente 20260814120000; backup novo; inbox API 200; sem restart) — 2026-11-01 ~21:10Z

- Autorização humana: "Aplicar somente essa (Recomendado)". Escopo: backup novo + `db:migrate:up VERSION=20260814120000` + validação metadata via token existente. Sem `db:migrate` genérico/prepare/seed, sem `20261024000001` ou outra pendência, sem modo por setores. Nenhum `.env` lido; nenhum segredo impresso/gravado; sem commit.
- Preflight read-only: HEAD `a661537d4` (2 docs modificados preservados); Rails/Sidekiq running restarts 0 imagem `chatwootnext:teste` `d539778b0ff0`; DB `chatwoot`; migration file idêntico host/imagem (`diff` limpo); versão `20260814120000` ausente (0), coluna ausente (`has_col=false`, 23 cols), `schema_migrations` 186; `db:migrate:status` 29 downs incluindo o alvo. Arquivo só adiciona boolean NOT NULL DEFAULT false — conforme esperado.
- Backup privado novo (com QA/migration Connecta): `pg_dump -Fc` via `chatwootnext-postgres-1` em `/home/thanos/.local/state/chatwootnext-connecta/backups/chatwoot-pre-20260814120000-20261101T210946Z.dump` (506292 bytes, dir 0700, arquivo 0600). Validado sem restaurar/ler dados: `pg_restore --list` 1284 entradas. Backups anteriores intactos.
- Migração: `docker exec chatwootnext-rails-1 bin/rails db:migrate:up VERSION=20260814120000` rc=0 (`add_column(:inboxes, :prevent_assignment_takeover, :boolean, default false, null false)`).
- Pós: `schema_migrations` 186→187 (só o alvo; `has20260814=1`, `has00001=0`); coluna boolean default `false` NOT NULL (`colnull=false`); inbox 24 cols; inboxes 1, members 1 (sem alteração de dados); downs 29→28.
- API com token JÁ EXISTENTE de User2 só em memória (runner interno, header `api_access_token`, só GETs, PII descartada; `AccessToken` 4→4, sem criar/rotacionar): `profile` 200 id=2, `account2` 200 id=2, inbox index 200 (count 1, ids=2, `has_pat=true`), inbox show 200 (id=2, `pat=false`). Detalhe: `User.find(2)` retorna STI `SuperAdmin` (sem `access_tokens`); token obtido via `AccessToken.where(owner_id: 2)` no mesmo processo.
- Sem restart necessário (Rails/Sidekiq running restarts 0, mesma imagem; API 200 sem recarga forçada). Health 200; QA 3/4 seguem agents sem inbox membership; `connecta_*` 10 tabelas todas 0 (sem binding/grant/outbox); flags desligadas (`CONNECTA_TRANSFER_ENABLED` ausente, gateway vazio, secret ausente). `git diff --check` limpo.

## Saude por unidades pronta para teste humano (candidata promovida, HMAC pareado, ACL/binding/membership) — 2026-11-01 ~21:28Z

- Imagem Saude promovida: candidata `wb-saude-backend:f422dcc-compat-src44e261e55953` (`sha256:b8dd0ff5be03`, labels `revision=f422dcc`, `dirty-patch`, `src/patch 44e261e5`) validada (parsers `parsePgSafePositiveId`/`parsePgEpoch` + `external_number` sem identifier no `dist`) tagueada como `wb-saude-backend:latest`. Rollbacks preservados: `rollback-5d6a159a050f` (= atual `5d6a159a050f`) criado agora + `rollback-aa906eaf735a` intacto. Nenhum novo build, nenhum `.env` lido, nenhum segredo em tag/label/log.
- Chatwoot pareado (novo `docker-compose.teste-lan.human-number-override.yml`, nao secreto, placeholders `${...:?}` + literais `enabled=true`, `account=2`, `platform=http://192.168.1.32:3000`, `reception=ea975324...`; suporte, sem commit): Rails/Sidekiq recriados só `--no-deps` com os 3 composes canônicos + override (pula migrations), HMAC privado nas duas direções em memória (sourcing `.secrets`, sem valor em argv/log), Baileys key efetiva preservada em memória. Pós: `human_enabled=true`, `account=2`, `platform_url` local, `p2f/f2p=present`, `reception` presente, restarts 0, imagem `d539778b0ff0`, `/health` 200, `schema_migrations` 187, coluna presente, inbox2 única.
- Saude pareada (novo `.runtime/compose.human-number-saude.yml`, ignorado pelo Git, placeholders + literais `base local`, `account2/inbox2`, `mode=external_number`, `hs_inbox=2`, `reception` UUID, `individual`, `enforce`; sem Ticketz/canal novo): token existente User2 via `AccessToken.where(owner_id:2)` em memória (sem rotação/arquivo novo, `AccessToken` 4→4), número Baileys via `Channel::Whatsapp` em memória, HMAC par direto (mesmos nomes, sem troca) em memória. Recriado só `wb-saude-backend` com os 4 composes + este (`--no-deps --no-build --force-recreate`). Pós: `mode=external_number`, `account2/inbox2/hs_inbox2`, `individual/enforce`, `p2f/f2p/token/number=present`, imagem `b8dd...`, `running healthy`, restarts 0, mount `certs:ro`, `/health`+`/ready` 200 (`dedicated`, `Facilita Saude`).
- Unidades/identidade/grants sincronizados por mecanismos reais (script idempotente via `dist` candidato, sem PII/segredo no log): Saude `org_units` 3 (`saude.recepcao` raiz + filhas, `accepts_cases`), `staff_users` 2 `operator active`, `links` 2 (`epoch=1`, `state=none`, QA 3/4), `grants` 6 publicados (`published=true`, `attendance_outbox` 11 `delivered acl.sync`, 0 pendente). Chatwoot projeção: `org_units` 3, `grants` 6 diretos sem leitura cruzada (3: Farmácia acompanhar/atender + transferir Hospital; 4 simétrico), `scoped_inboxes` 0 então, `outbox` 0 pendente, `acl_sync_state` 1, `epochs` 1/1, QA agents confirmados não superadmin sem `InboxMember` então. Ticketz intocado.
- Heartbeat/ACL verificados por mais de um ciclo (serviços HMAC reais, sem negócio): `last_heartbeat_at` 21:21:58 → 21:23:33 → 21:25:48 → 21:27:18 UTC, `verified=true fresh=true admin=false` para 3/4, TTL 120s compatível, hooks carregados (modelos `ScopedInbox`/`Projection`/`Gate` sem erro). `git diff --check` limpo nos dois repos.
- Binding/enforcement/transfer/callbacks só depois dos requisitos: `connecta_scoped_inboxes` inbox2 `enforce` sem `maintenance` (`verify_marked_inboxes!` ok), `Feature.enabled` true + `enforce` autoriza human-number sem misturar legado (`CONNECTA_TRANSFER_ENABLED` segue false). Callback local `webhooks` conta2 0→1 (`http://192.168.1.32:9090/chatwoot/webhook`, `message_created,conversation_status_changed`, segredo = `CHATWOOT_WEBHOOK_SECRET` vigente via `ENV`, sem valor em arquivo/argv; outros preservados). Nenhum callback externo alterado/chamado.
- Membership QA por último: `InboxMember` inbox2 [2] → [2,3,4] (`find_or_create_by!`, admin 2 preservado). Pós-membership reconfirmado por mais de um ciclo: `verified/fresh true`, `admin false`, `enforce`, heartbeat 21:27:18, `/health` 200 ambos. Sem acesso inseguro liberado; sem conversa/caso/mensagem/protocolo criado; sem transferência executada; sem admissão de antigas (acesso administrativo mantido).
- Validação técnica (sem funcional): `profile/account/inbox index/show` 200 com token existente, Baileys `/status`+`/status/auth` 200, `AccessToken` 4, `prevent_assignment_takeover` true, roles `agent`, `SuperAdmin` 0 para QA, backups privados preservados (paths em `.../backups/`, 0600/0700, sem leitura de conteúdo). Humano fará testes funcionais.

## Correcao operacional pos-Explorer (transferir na origem + override persistente) — 2026-11-01 ~21:36Z

- Grants: Explorer confirmou QA3 sem `transferir` Farmácia e QA4 sem `transferir` Hospital; `transfer_policy.rb:51` e `transfer.ts:62,98` exigem `transferir` na origem (`fromUnit`), destino só não basta. Adicionados idempotentemente via `grantAndPublish` no `wb-saude-backend` candidato (`b8dd...`): `transferir` Farmácia para QA3 e `transferir` Hospital para QA4, ambos `published=true`. Seis grants anteriores preservados, sem leitura cruzada/ancestral, sem substituir acompanhar/atender.
- Pós-sync HMAC real: Saude `staff_grants` 6→8 (4 por staff), `attendance_outbox` 11→13 `delivered acl.sync`; Chatwoot `connecta_user_grants` 6→8 (3: 4, 4: 4; QA3 transfere Farmácia+Hospital lendo só Farmácia, QA4 simétrico), `acl_sync_state` heartbeat 21:35:33 UTC `verified/fresh true admin false` TTL120. Nenhuma transferência/caso/mensagem criada ou chamada.
- Override Saude reconciliado no HOST via ferramenta nativa: `/home/thanos/conectacidade/apps/whatsapp-platform/.runtime/compose.human-number-saude.yml` existe (`stat` 1601 bytes, 664, 2026-11-01 21:20:33; `ls` lista; leitura nativa só placeholders `${...:?}` + literais, 0 segredos longos). Ignorado pelo Git (`.gitignore:11:.runtime/`), mesmo padrão do `compose.dev-saude.yml`; procedimento documentado no próprio arquivo (4 composes + este, `--no-deps --no-build backend`). Falha do Explorer veio de filesystem descartável de sandbox, não do host.
- Chatwoot `docker-compose.teste-lan.human-number-override.yml` existe no host (1437 bytes após aviso, não ignorado, suporte sem commit); cabeçalho agora adverte que recriar Rails/Sidekiq só com os 2 composes antigos remove flags — usar sempre os 3 composes. Nenhum serviço recriado nesta correção (todos `running healthy`, restarts 0); sem restart desnecessário.
- Saude publica `200` sem payload pessoal via `python3 urllib` no host. `git diff --check` limpo. Sem teste funcional, segredo ou PII.

## Triagem inbox2 Farmacia/Hospital cadastrada (somente metadata) — 2026-11-01 ~21:43Z

- Antes: `public_triage_options` 0 linhas (repository `humanServiceReceptionRepo.options()` vazio); nenhum conflito. Contrato lido em `humanServiceReceptionRepo.ts:20-24` e `reception.ts:116-148` (menu 1..N + 0 Outros para Recepcao, vazio direto para Recepcao). Sem chamar reception/ingress/sendMessage.
- Cadastro idempotente em transacao (`ON_ERROR_STOP`, `WHERE NOT EXISTS` por `org_unit_id` existente): posicao 1 Farmácia (`57be7f6b...`) e 2 Hospital (`ad794d88...`), `enabled true`. Fallback 0/sem escolha preservado via `HUMAN_SERVICE_RECEPTION_UNIT_ID` (`ea975324...`); Ticketz preservado (`human_handoff_departments` 1). Nenhum codigo/migration/DDL novo.
- Depois via mesmo repository: 1 Farmácia e 2 Hospital habilitados e com unidades habilitadas. Grants inalterados (8 ambos bancos, 4/QA, leitura só própria). ACL `verified/fresh true admin false`, binding `enforce`, membros [2,3,4], heartbeat 21:42:18 UTC, `/health` 200 ambos. Sem conversa/protocolo/mensagem/transferência. Sem restart (repository lê dinamicamente). `git diff --check` limpo.

## Helper interativo de acesso admin local preparado (sem alteracao de credenciais) — 2026-11-01 ~22:17Z

- Criado helper privado nao secreto fora do Git: `/home/thanos/.local/state/chatwootnext-connecta/bin/set-local-admin-access` (dirs 0700, script 0700, `bash -n` OK, payloads Ruby `Syntax OK` no ruby do container). Nenhuma credencial literal no script; nenhum arquivo `admin-access.secrets` criado.
- Fluxo: `--check` somente leitura (sem senha, sem escrita) ou modo escrita que pede login por `read` e senha por `read -s` (sem eco/historico), mantem valores so em memoria (sem export/argv/log/arquivo) e os envia por stdin ao `rails runner` no container local `chatwootnext-rails-1`; codigo Ruby estatico via argv.
- Guardas sem escrita: alvo fixo users.id=2, STI SuperAdmin, provider email, administrator da conta 2, login novo nao em uso (email/uid), validacoes normais do modelo antes de gravar. Hash por `password=` (Devise/Bcrypt); `skip_reconfirmation!` pontual so se o email mudar; AccessToken preservado e rechecado por ids (sem reset); PubSub gira por desenho (aviso de possivel novo login). Saida so com `ok=` e booleanos seguros.
- Validacao desta etapa: `--check` rc=0 (`target_found/is_superadmin/provider_email/confirmed/account2_admin=true`, `api_token_count=1`, `access_tokens_total=4`), `git diff --check` limpo. DB e credenciais inalterados; humano ainda precisa executar o comando.
