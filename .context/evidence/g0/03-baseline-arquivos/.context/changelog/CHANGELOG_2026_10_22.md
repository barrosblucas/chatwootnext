# Changelog 2026-10-22

## Added

- `spec/requests/connecta/route_inventory_spec.rb`: lê as rotas reais (`Rails.application.routes.routes`) e falha para rota relevante sem superfície da matriz §10.1 (provisória, ver PROJECT_STATE); rotas não relacionadas ficam fora do conjunto verificado. NÃO EXECUTADA.
- `scripts/connecta/g0_test_env.sh`: roteiro de preparo do ambiente de teste G0. Padrão dry-run (imprime comandos, checa pré-condições); `--apply` e `--teardown` exigem autorização. Alvos: projeto `conecta-baileys-g0-test`, banco `conecta_baileys_g0_test`, Postgres em `127.0.0.1:55432`, Redis em `127.0.0.1:56379`.
- `scripts/connecta/g0-test-services.compose.yml`: Postgres `pgvector/pgvector:pg16` e Redis descartáveis, portas só em loopback, volume próprio, sem Redis persistente.
- `.context/`: contexto mínimo criado a partir do template padrão e preenchido com fatos verificados.

## Changed

- Nenhum arquivo de `app/`, `config/`, `Gemfile*`, lockfiles, `.ruby-version`, `AGENTS.md` ou `CLAUDE.md` foi alterado.

## Fixed

- Nada.

## Tests

- `ruby -c spec/requests/connecta/route_inventory_spec.rb` com Ruby 4.0.7 (não é o runtime homologado 3.4.4): Syntax OK.
- `bash -n scripts/connecta/g0_test_env.sh`: OK.
- `docker compose -p conecta-baileys-g0-test -f scripts/connecta/g0-test-services.compose.yml config --quiet`: OK (leitura, sem subir serviços).
- Parse YAML do compose: serviços `postgres` e `redis`; portas `127.0.0.1:55432:5432` e `127.0.0.1:56379:6379`.
- `scripts/connecta/g0_test_env.sh` (dry-run): executado. Resultado: Ruby 3.4.4 "falta" (não instalado); demais pré-condições ok; nenhum comando de preparo executado.
- Whitespace e newline final dos três arquivos novos: limpos.
- NÃO EXECUTADO: `bundle exec rspec spec/requests/connecta/route_inventory_spec.rb` (Ruby 3.4.4 e banco de teste indisponíveis; sem autorização para instalar/subir).
- NÃO EXECUTADO: RuboCop, ESLint, Vitest (dependências não instaladas), shellcheck (não instalado).

## Docs

- Docs: criado `.context/` a partir do template padrão.
- `.context/` preenchido com fatos verificados: `AI-GOVERNANCE.md`, `architecture.md`, `REPOMAP.md`, `PROJECT_STATE.md`, `gotchas.md` preenchidos com fatos verificados.
- Plano Baileys não lido: a leitura de `/home/thanos/conectacidade/.worktrees/app-solicitacoes/.context/plans/2026-10-22-atendimento-dois-numeros-baileys.md` foi negada pelo context-mode (fora da raiz do projeto). Nenhuma troca de ferramenta para contornar. Antes da negação, `Read` foi usado só na linha 1. Ver PROJECT_STATE.

## Process

- Worktree criado para a tarefa, conforme o fluxo do fork: `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep` a partir de `main` (7a46faca9). A árvore original `/home/thanos/chatwootnext` permanece em `main`, limpa.
- Nenhum commit, push, merge ou PR. Sem `.env` lido ou copiado.
- Hooks do husky (`pre-commit`, `pre-push`) não rodam na criação de worktree.

## Correções do Juiz T2 (REQUIRED_FIXES do preparo G0)

Ajustes sobre o preparo do mesmo dia. G0 segue ABERTO. Nada foi executado: sem Ruby 3.4.4, Docker, banco, `bundle install` nem spec. Os trechos abaixo substituem as descrições anteriores deste arquivo.

### Fixed
- REQUIRED_FIX 1 (AC1): superfícies omitidas incluídas em `spec/requests/connecta/route_inventory_spec.rb`: deduplicação (`api/v1/accounts/actions`), ações em lote (`bulk_actions`), filtros salvos (`custom_filters`), anexos e proxies (`active_storage`, `slack_uploads`, `contacts/attachments`), integrações, widget (`api/v1/widget`, `widgets`), público (`public/api/v1`), plataforma, super admin e Enterprise. Catch-all `/app/*params` (`config/routes.rb:20`) e `resource :app` (`config/routes.rb:706-708`) classificados; a URL de conversa é verificada por `recognize_path` (cai em `dashboard#index`). QR/status (`inboxes#setup_channel_provider`, `#health`, `#import_whatsapp_session`) e `/cable` são superfícies obrigatórias. Fronteiras de autenticação registradas por superfície.
- REQUIRED_FIX 2 (AC2): Dotenv bloqueado pela recusa do runner (`.env*` na raiz, exceto `*.example`); ambiente herdado descartado por `env -i`; alvo efetivo de `config/database.yml` verificado de forma estática antes de `db:create`/`db:schema:load` e a guarda confere o ambiente antes de `rails_helper`.
- REQUIRED_FIX 3 (AC2): `--spec` reutiliza o ambiente isolado. Guarda chamada em `route_inventory_spec.rb:1-3`, antes de `require 'rails_helper'`. Comando impresso e documentação atualizados (`scripts/connecta/g0_test_env.sh --spec --apply`).
- REQUIRED_FIX 4 (AC2/AC5): Docker restrito a contexto local (`unix://`). Containers e redes com o nome do projeto só são aceitos se o label `com.docker.compose.project` for o deste projeto; caso contrário o runner recusa `up` e `down`. Volume continua exigido como ausente.
- REQUIRED_FIX 5 (AC2): `trust` removido de `scripts/connecta/g0-test-services.compose.yml`. Postgres exige `POSTGRES_PASSWORD` (`${G0_SYNTHETIC_SECRET:?...}`); Redis exige `requirepass` via `REDISCLI_AUTH`, inclusive no healthcheck. A senha é gerada no `--apply` em `~/.cache/connecta-g0-test/synthetic-secret` (0600, fora do repo) e nunca impressa.
- REQUIRED_FIX 6 (AC2/AC5): `pnpm install` removido do preparo; `package.json:16` (`prepare: husky install`) não roda. Nenhum hook instalado nem configuração Git alterada.
- REQUIRED_FIX 7 (AC4): regras sem fonte no repo saíram de `AI-GOVERNANCE.md` e foram listadas em "Propostas sem vigência". `README.md` do `.context` deixou de apresentar a tabela como obrigatória. Regras reais citadas com fonte (`AGENTS.md`, `CLAUDE.md`).

### Changed
- `spec/requests/connecta/route_inventory_spec.rb`: reescrito. Lê as rotas reais, classifica por área (`surfaces`), mantém infraestrutura explícita (`infra`) e falha se alguma rota não cair em nenhum dos dois. Remove o teste antigo de "rotas não relacionadas", que se apoiava em prefixos e deixava áreas inteiras de fora.
- `scripts/connecta/g0_test_env.sh`: reescrito. Modos: dry-run (padrão), `--apply`, `--spec` e `--teardown`. Dry-run não altera nada. Argumentos inválidos saem com código 2. Sem `pnpm install`.
- `scripts/connecta/g0-test-services.compose.yml`: senhas obrigatórias (ver REQUIRED_FIX 5); portas inalteradas (127.0.0.1:55432, 127.0.0.1:56379).
- `.context/AI-GOVERNANCE.md`, `README.md`, `PROJECT_STATE.md`, `gotchas.md` e `REPOMAP.md`: ver REQUIRED_FIX 7 e as decisões pendentes em `PROJECT_STATE.md`.

### Added
- `spec/support/connecta/g0_target_guard.rb`: guarda sem boot Rails. Exige variáveis do alvo G0 e senhas presentes; recusa `DATABASE_URL` e arquivos `.env*` na raiz (exceto `*.example`). Só define métodos na carga, por isso o glob de `spec/support` é inofensivo.

### Tests
- `bash -n scripts/connecta/g0_test_env.sh`: OK.
- `ruby -c` com Ruby 4.0.7 (`~/.local/share/mise/installs/ruby/4.0.7/bin/ruby`) em `route_inventory_spec.rb` e `g0_target_guard.rb`: Syntax OK. O `ruby` do shell não tem versão definida nesta worktree.
- `git diff --no-index --check` nos quatro arquivos novos: sem espaços em branco.
- Guarda sem Rails: ambiente vazio aborta (exit 1) listando as chaves fora do alvo, sem imprimir valores; ambiente do alvo G0 com valores de teste passa; `DATABASE_URL` herdada aborta.
- Compose: `docker compose ... config --quiet` com valor dummy: exit 0. Sem `G0_SYNTHETIC_SECRET`: erro de interpolação, exit 1.
- Alvo efetivo de `config/database.yml` (leitura estática, Ruby 4.0.7): alvo G0 → 0; `chatwoot_test` na porta 5432 → 1.
- Runner, dry-run sem `--apply`: `prepare`, `--spec` e `--teardown`. Só checagens de leitura (`docker info`, contexto Docker, `docker ps`, `docker volume inspect`, conexão TCP de porta). Resultado: Ruby 3.4.4 em falta; contexto Docker local ok; portas livres ok; volume ausente ok; sem `.env*` real na raiz ok; segredo ausente ok; rejeição de argumentos ok.
- Limitação: a classificação não foi executada contra as rotas em runtime. Foi conferida por leitura de `config/routes.rb` (823 linhas), incluindo rotas aninhadas (portais, `conference`, `teams`).
- NÃO EXECUTADO: `bundle exec rspec spec/requests/connecta/route_inventory_spec.rb`; `--apply`, `--spec --apply` e `--teardown --apply`; `docker compose up`/`down`; `bundle install`; RuboCop; ESLint; Vitest; shellcheck (não instalado).

### Docs
- Pendências com o efeito prático de cada opção (`.env` na raiz, abrangência da guarda, carga da spec fora do alvo, Redis, segredo, frontend) em `PROJECT_STATE.md`.

## Segunda revisão T2 (REQUIRED_FIXES 1-4)

Mesmo TASK_ID `atendimento-baileys`; contagem de rejeições mantida. Só correção estática: nenhum serviço, banco, RSpec, Rails, `docker compose up/down` ou consulta ao daemon. G0 segue ABERTO.

### Fixed
- REQUIRED_FIX 1 (AC1): marcadores "a verificar" substituídos por fontes do código em `spec/requests/connecta/route_inventory_spec.rb`:
  - Slack: `app/controllers/slack_uploads_controller.rb:1,15-17`. Herda `ApplicationController`, sem exigir usuário; o único controle é a chave aleatória do blob.
  - ActionCable: `app/channels/application_cable/connection.rb:1-2` é vazio e não autentica. `app/channels/room_channel.rb:42-48` identifica por `pubsub_token`; `:54` e `:56` definem a conta (contato ou membership).
  - Público: `public_controller.rb:3` (sem Devise); caixa por `identifier` em `public/api/v1/inboxes_controller.rb:12-15`; HMAC só se `hmac_mandatory` ou `identifier_hash` (`public/api/v1/inboxes/contacts_controller.rb:32`).
  - Conta e relatórios: `api/v1/accounts/base_controller.rb:1,4-5` herda `Api::BaseController` (`api/base_controller.rb:4-6`). Relatórios v2: `reports_controller.rb:105-107` → `ReportPolicy#view?` (administrador, `report_policy.rb:2-4`). Demais ações: policy por ação, não auditada item a item.
  - Canais externos: validados por WhatsApp/Instagram (`verify_meta_signature!`), TikTok e Shopify (HMAC), Line (`webhooks/line_events_job.rb:7`), Stripe e Firecrawl (Enterprise). Sem validação de assinatura no código: Twitter/X POST (`webhooks_controller.rb:9-15`), Telegram (`bot_token` na URL, `webhooks/telegram_controller.rb:2`), SMS (`webhooks/sms_controller.rb:2`), Twilio callback, status e voz (`twilio/callback_controller.rb:2`, `twilio/delivery_status_controller.rb:2`, `enterprise/.../twilio/voice_controller.rb:9`).
  - Caixas: `fetch_inbox` (`inboxes_controller.rb:3,178-180`) cobre QR, sessão e saúde. A referência anterior, `:101`, era só um comentário.
  - Enterprise API: `enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb:1` herda `Api::BaseController`, único controller da pasta.
- REQUIRED_FIX 2 (AC2): `scripts/connecta/g0_test_env.sh` checa o contexto Docker local antes de qualquer consulta ao daemon, `docker info` incluso. Vale para os três modos, com e sem `--apply`. Contexto não local sai com `exit 1` na hora. Antes, `docker info` e `docker ps` rodavam antes da checagem e o dry-run seguia.
- REQUIRED_FIX 3 (AC2): recursos do projeto são selecionados por nome e por rótulo `com.docker.compose.project`.
  - Contêiner só é aceito se `com.docker.compose.project.config_files` apontar para o `g0-test-services.compose.yml` deste worktree. Caminho normalizado com `pwd -P`, porque `realpath -m` não existe no macOS.
  - Rede: o Compose não grava arquivo de configuração em redes (`prepareNetworks` em `pkg/compose/create.go`, citado na documentação do Compose v2.39.1, via Context7). A origem é a dos contêineres anexados, e rede sem contêiner é recusada.
  - A checagem roda em `prepare`, `--spec` e `--teardown`, antes de `up`, `down` e da spec.
- REQUIRED_FIX 4 (AC7): cinco decisões registradas como resolvidas em `PROJECT_STATE.md`. `REPOMAP.md` corrige o suporte auto-carregado: `spec/rails_helper.rb:34` carrega `spec/support/**`, e só a execução `verify!` é do inventário.

### Changed
- `scripts/connecta/g0_test_env.sh`: ordem das checagens, origem por rótulo e rejeição. Sem modo novo, sem alteração de serviço, volume ou porta.
- `spec/requests/connecta/route_inventory_spec.rb`: só os textos `auth:` (com arquivo:linha). Nenhuma regra de classificação mudou.
- `.context/PROJECT_STATE.md` e `.context/REPOMAP.md`: decisões resolvidas, suporte auto-carregado e pendências de canais sem validação.

### Tests
- `bash -n scripts/connecta/g0_test_env.sh`: OK.
- `ruby -c` com Ruby 4.0.7 em `route_inventory_spec.rb`: Syntax OK. Não é o runtime 3.4.4.
- Stub inerte de `docker` em `/tmp/g0-stub` (fora do repo, sem daemon, `HOME` de teste sem `~/.cache` real): `run_stub_tests.sh`, 18 asserts, 0 falhas. Cobre:
  - contexto remoto em `prepare`, `--spec` e `--teardown` (dry-run): só `docker context inspect`, exit 1;
  - contêiner de outra origem recusado antes de `compose down` com `--apply`;
  - contêiner próprio aceito e `down` executado;
  - rede sem contêiner recusada; rede com contêiner de outra origem recusada; rede própria aceita; rede que só casa pelo nome recusada;
  - spec em dry-run reporta origem e não executa `compose`.
- `docker context inspect` (leitura de configuração cliente): `default unix:///var/run/docker.sock`.
- Linhas acima de 150 colunas nos dois arquivos: nenhuma. Sem espaço no fim das linhas.
- NÃO EXECUTADO: `docker info`, `docker ps` e demais consultas reais ao daemon; `bundle exec rspec`; `docker compose up/down`; `--apply`; RuboCop (gems não instaladas); shellcheck (não instalado).
- Limitação: o stub valida a lógica do runner. O rótulo `config_files` em contêineres e a ausência dele em redes não foram confirmados em daemon real. Confirmar na primeira execução autorizada.

## Terceira revisão T2 (correção de descrições, REQUIRED_FIXES 1-2, mesmo TASK_ID)

### Fixed
- `spec/requests/connecta/route_inventory_spec.rb`: textos `auth:` de widget, CSAT e API pública corrigidos com fontes. Só texto; classificação e testes não mudaram.
  - Widget: `X-Auth-Token` é JWT HS256 assinado com `secret_key_base` (`concerns/website_token_helper.rb:3`, `services/base_token_service.rb:9,20-26`). Identificação por `identifier`; HMAC-SHA256 só verifica quando há `identifier_hash` ou `hmac_mandatory` (`api/v1/widget/contacts_controller.rb:4-5,66-85`). Sem `authenticate_user!` no widget (`application_controller.rb:10,16-19` só carrega o usuário).
  - CSAT público: a conversa é identificada só pelo UUID em `:id` (`public/api/v1/csat_survey_controller.rb:18`), sem HMAC nem token; `update` aceito em até 14 dias (`:8,29-31`).
  - API pública: HMAC só em contatos (`public/api/v1/inboxes/contacts_controller.rb:3,31-33`). Mensagens não chamam HMAC (`public/api/v1/inboxes/messages_controller.rb:1,8-12`).
- `.context/PROJECT_STATE.md:22`: alcance da guarda `.env` corrigido. A checagem roda em `prepare` (`scripts/connecta/g0_test_env.sh:171`) e em `--spec` (`:182`); `--teardown` não a executa (`:191-195`). O texto anterior dizia que valia também para `--teardown`. Runner não alterado.

### Tests
- `mise exec ruby@4.0.7 -- ruby -c spec/requests/connecta/route_inventory_spec.rb`: Syntax OK. Ruby 4.0.7 já existente; não é o runtime 3.4.4 e nada foi instalado.
- Linhas da spec acima de 150 colunas: nenhuma.
- NÃO EXECUTADO: RSpec, Rails, Docker, banco, Redis, instalações. Nenhum teste ou regra de autenticação alterado.

## Execução G0 (Fase 0, autorizada): preparo local, spec T0.1 e correções

Autorização: citação literal no briefing do orquestrador (ambiente local de desenvolvimento, dados sintéticos, alvo G0 apenas). Detalhes, comandos e códigos de saída: `.context/evidence/g0/01-execucao-preparo-e-validacao.md`; inventário: `.context/evidence/g0/02-inventario-t0-1.md`. G0 segue **ABERTO**. Nenhuma prova de EVID2..8, ACL ou transporte.

### Added
- `.context/evidence/g0/00-baseline-preparo.md` e `00-baseline-sha256.txt`: SHA256 dos 16 arquivos de preparo, registrados antes de qualquer alteração. É baseline a partir de agora, não prova histórica.
- Ambiente local fora do repo (não versionado, reversível): Ruby 3.4.4 e bundler 2.5.16 em `~/.cache/connecta-g0-test/toolchain/`; 378 gems em `.bundle/gems` (ignorado).
- Serviços do projeto `conecta-baileys-g0-test` em execução (Postgres `pgvector/pgvector:pg16` e Redis `redis:alpine`, healthy, somente `127.0.0.1`). Banco `conecta_baileys_g0_test` com 114 tabelas e schema carregado.

### Changed
- `spec/requests/connecta/route_inventory_spec.rb`: 22 rotas reclassificadas, sem remover regra e sem reduzir cobertura. Montagens e redirects (`/assets`, `/`, `/auth/:provider`) e rotas Devise do super admin (cadastro, senha, confirmação, OAuth/SAML) recebem fronteira com `arquivo:linha`. Linha longa quebrada.
- `spec/support/connecta/g0_target_guard.rb`: estrutura compacta (`module Connecta::G0TargetGuard`, exigida pelo `CLAUDE.md`). Lógica e mensagens iguais.
- `.context/PROJECT_STATE.md`, `REPOMAP.md`, `gotchas.md`: estado, pastas e armadilhas atualizados. `architecture.md`: sem mudança de fronteira ou stack do produto; não alterado.

### Fixed
- Spec T0.1: primeira execução com 22 rotas sem superfície (`3 examples, 1 failure`). Após a reclassificação: `3 examples, 0 failures`.
- Toolchain do Ruby de teste: o `configure` do Ruby 3.4.4 não detectou `stdbool.h` com GCC 15 (padrão C23), e as gems nativas falhavam com `unknown type name 'bool'`. Corrigido reinstalando a mesma versão e fonte oficial com `ac_cv_header_stdbool_h=yes`. Sem fallback para Ruby 4.

### Tests
- `scripts/connecta/g0_test_env.sh --spec --apply` (alvo G0): exit 0, `3 examples, 0 failures`.
- `bundle exec rubocop` nos dois arquivos Ruby do G0: sem ofensas (exit 0).
- `bash -n scripts/connecta/g0_test_env.sh`: exit 0.
- Guarda sem alvo G0: exit 1, recusa antes do Rails.
- Host sem credencial: Postgres recusa (`fe_sendauth: no password supplied`); Redis recusa (`NOAUTH`).
- `sha256sum -c` do baseline: 14 OK; 2 alterados por desenho (spec e guard).
- NÃO EXECUTADO: request de runtime nas rotas de cadastro do super admin (risco aberto em `evidence/g0/02`); ESLint (sem JS alterado); shellcheck (não instalado); T0.2 a T0.7.

### Process
- O `--apply` do runner terminou com exit 5 no `bundle install`. Containers ficaram de pé. Como o runner não é reexecutável após falha parcial (decisão pendente em `PROJECT_STATE.md`), os passos seguintes foram executados à mão com o mesmo ambiente.
- `mise uninstall ruby@3.4.4` e reinstalação só dentro da pasta da tarefa. Nenhuma configuração global do mise, `.ruby-version` ou `.mise.toml` foi alterada.
- Nenhum arquivo rastreado modificado; `Gemfile`, `Gemfile.lock` e `.ruby-version` iguais ao HEAD. Nenhum commit, push, merge ou PR.
