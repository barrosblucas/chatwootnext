# Gotchas — chatwootnext

Armadilhas conhecidas: comportamento não óbvio ou bug que já custou uma rodada.
Registre só fatos verificados. Formato de cada item (uma linha):

`- AAAA-MM-DD — <fato em 1 linha> — evidência: <arquivo:linha | comando | run>`

- 2026-10-22 — `get '/app/*params'` (dashboard#index) vem antes de `/app/accounts/:account_id/conversations/:id`, então o GET dessa URL cai no catch-all da SPA — evidência: config/routes.rb:20 e config/routes.rb:708
- 2026-10-22 — a rota `resources :conversations` aninhada em `resource :app` aponta para o controller `conversations`, que não existe em app/controllers — evidência: config/routes.rb:706-708 e `ls app/controllers/conversations_controller.rb` (inexistente)
- 2026-10-22 — o `ruby` do mise instala a versão do `.ruby-version` (3.4.4) se estiver ausente; checagens fora de `--apply` precisam de `MISE_NOT_FOUND_AUTO_INSTALL=0` — evidência: `mise settings get not_found_auto_install` = true; scripts/connecta/g0_test_env.sh (função `ruby_is_3_4_4`)
- 2026-10-22 — `docker-compose.test.yaml` publica 5432 e 6379 em todas as interfaces e usa volumes genéricos; não serve para testes isolados (G0) — evidência: docker-compose.test.yaml:45 e docker-compose.test.yaml:59
- 2026-10-22 — `config/application.rb` chama `Dotenv::Rails.load`, que lê `.env*` da raiz antes de qualquer spec; variável já exportada não é sobrescrita, mas variável ausente é preenchida pelo arquivo. Por isso o runner recusa a execução se houver `.env*` na raiz (exceto `*.example`) — evidência: config/application.rb:15; doc do dotenv consultada via Context7 (/bkeepers/dotenv: "Existing environment variables are not overwritten by default")
- 2026-10-22 — a senha de `config/database.yml` no ambiente production tem padrão literal `chatwoot_prod` — evidência: config/database.yml:32
- 2026-10-22 — `Redis::Config` lê `REDIS_URL` e `REDIS_PASSWORD` em campos separados; a senha precisa ir em `REDIS_PASSWORD` — evidência: lib/redis/config.rb:14-15
- 2026-10-22 — em `Rails.env.test?` o Redis do app é `MockRedis` e o cable usa adapter `test`; um Redis real no G0 não é usado pelo app nesse ambiente — evidência: config/initializers/01_redis.rb:10; config/cable.yml:12-13
- 2026-10-22 — `pnpm install` executa o script `prepare` (`husky install`) — evidência: package.json:16
- 2026-10-22 — `.env.fazer.example` existe na raiz junto de `.env.example`; checagens que procuram `.env*` precisam excluir `*.example` — evidência: `ls -A` na raiz da worktree
- 2026-10-22 — Ruby 3.4.4 compilado com GCC 15 (padrão C23) falha no teste `stdbool.h` do configure (`#ifndef bool`); `HAVE_STDBOOL_H` fica indefinido e gems nativas com `-std=c99` quebram com `unknown type name 'bool'`; correção testada: `ac_cv_header_stdbool_h=yes` no `mise install` — evidência: probe com gcc (padrão falha, `-std=gnu17` passa); `bootsnap-1.16.0/ext/bootsnap/extconf.rb:7`; falha de `google-protobuf 3.25.7` no `bundle install` da 1ª tentativa (`evidence/g0/01`, falha 1)
- 2026-10-22 — mise instala Ruby pré-compilado de terceiros (`jdx/ruby`) por padrão desde 2026.8.0; para compilar da fonte oficial use `MISE_RUBY_COMPILE=true` — evidência: docs `jdx/mise` (`docs/lang/ruby.md`, via Context7) e release notes 2026.8.0
- 2026-10-22 — o runner `--apply` não é reexecutável após falha parcial: as pré-condições de volume ausente e de porta livre reprovam com os recursos já criados — evidência: `scripts/connecta/g0_test_env.sh:175-176`
- 2026-10-22 — o Postgres do compose cria `conecta_baileys_g0_test` na inicialização (`POSTGRES_DB`); `rails db:create` responde "already exists" — evidência: `~/.cache/connecta-g0-test/logs/db-setup.log`
- 2026-10-22 — dentro do container o loopback aceita Postgres sem senha e o `redis-cli` autentica por `REDISCLI_AUTH`; teste de autenticação deve ser feito do host pela porta publicada — evidência: `evidence/g0/01` item 18 (host: `fe_sendauth: no password supplied` e `NOAUTH`)
- 2026-10-22 — rotas sem controller (montagens e redirects) escapam da classificação por controller: `/assets` (sprockets-rails 3.4.2, `railtie.rb:224-225`), `/` (engine SES, aws-actionmailbox-ses 0.1.0, `engine.rb:13-15`), `/auth/:provider` (devise_token_auth 1.2.5, `rails/routes.rb:76`) — evidência: 1ª execução da spec (22 rotas) e `evidence/g0/02`
- 2026-10-22 — `SuperAdmin < User` herda os módulos Devise do usuário (inclui `registerable` e `omniauthable`), por isso existem rotas de cadastro e OAuth do super admin — evidência: `app/models/super_admin.rb:48`, `app/models/user.rb:60-69`, `rails runner` (`POST /super_admin` → `devise/registrations#create`)
