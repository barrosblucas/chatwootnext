# G0 — execução do preparo e validação (Fase 0, autorizada)

- Data (UTC): 2026-10-22, a partir de 14:39Z (baseline); horários de cada etapa estão nos logs citados abaixo.
- Autorização: citação literal do briefing do orquestrador. Alvo: máquina local, worktree `chatwootnext-connecta-g0-prep`, projeto Compose `conecta-baileys-g0-test`, Postgres `127.0.0.1:55432`, Redis `127.0.0.1:56379`, banco `conecta_baileys_g0_test`, somente dados sintéticos.
- Fora deste registro: servidor remoto, produção, pareamento, WAHA, instalações globais, `apt`/`sudo`.
- Estado do gate: **G0 continua ABERTO**. Este registro não aprova o preparo nem o G0. EVID2..8 e ACL/transporte não foram provados aqui.
- Logs fora do repo: `~/.cache/connecta-g0-test/logs/` (não versionados). Segredo sintético: `~/.cache/connecta-g0-test/synthetic-secret` (modo 0600; conteúdo nunca impresso).

## Ambiente real

| Item | Valor verificado | Como foi verificado |
|---|---|---|
| Ruby | 3.4.4 (2025-05-14 revision a38531fd3f) +PRISM, x86_64-linux | `ruby -v` do prefixo da tarefa |
| Prefixo Ruby | `~/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4` | fora do PATH global; sem alteração de `.ruby-version`/`.mise.toml` |
| Fonte Ruby | `https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.4.tar.gz` (host oficial, único no log do build) | log do mise/ruby-build |
| SHA256 da fonte | `a0597bfdf312e010efd1effaa8d7f1d7833146fdc17950caa8158ffa3dcbfa85` = valor publicado em ruby-lang.org (release 3.4.4) | `sha256sum` do tarball no cache do ruby-build (2ª instalação) |
| Compilação | a partir da fonte (`MISE_RUBY_COMPILE=true`); o padrão do mise (binário pré-compilado de terceiros) foi descartado | variável de ambiente no `mise install` |
| mise | 2026.10.3 (binário do usuário), dados/cache/estado/config em `~/.cache/connecta-g0-test/toolchain/` | variáveis `MISE_*` no comando |
| Compilador | gcc 15.2.0 (Ubuntu) | `gcc --version` |
| Bundler | 2.5.16 (= `BUNDLED WITH` do lockfile), instalado no prefixo da tarefa | `bundle -v` |
| Gems | `Bundle complete! 153 Gemfile dependencies, 378 gems now installed.` (`BUNDLE_PATH=.bundle/gems`, ignorado pelo git) | `~/.cache/connecta-g0-test/logs/bundle-install.log` |
| Lockfile/Gemfile/.ruby-version | SHA256 idêntico ao HEAD `7a46faca9` (não alterados) | `sha256sum` vs `git show HEAD:...` |
| Docker | server 29.6.2; contexto `default` = `unix:///var/run/docker.sock`; Compose v5.3.1 | `docker info`, `docker context inspect` |
| Postgres | `pgvector/pgvector:pg16`, healthy, `127.0.0.1:55432->5432` | `docker ps`, `docker port` |
| Redis | `redis:alpine`, healthy, `127.0.0.1:56379->6379`, `requirepass` via `REDISCLI_AUTH` | `docker ps`, `docker port` |
| Propriedade | containers com `com.docker.compose.project=conecta-baileys-g0-test` e `config_files` = `scripts/connecta/g0-test-services.compose.yml` deste worktree | `docker inspect` (labels) |
| Volume/rede | `conecta-baileys-g0-test_g0_postgres`; rede `conecta-baileys-g0-test_default` (criados pelo projeto) | `docker volume ls` / `docker network ls` |
| Banco | `conecta_baileys_g0_test`: 114 tabelas em `public`; `schema_migrations` máx. `20260718000000`; extensão `vector` presente | `psql` dentro do container, consultas somente de leitura |

## Sequência de comandos (com código de saída)

1. Baseline: `sha256sum` dos 16 arquivos de preparo antes de qualquer alteração → `00-baseline-sha256.txt` (`sha256sum -c`: 16/16 OK no momento do registro).
2. `mise install ruby@3.4.4` (1ª tentativa, fonte oficial) → exit 0. Ruby compilado, mas o `bundle install` seguinte falhou (ver falha 1).
3. `scripts/connecta/g0_test_env.sh` (dry-run `prepare`) → exit 0; todas as pré-condições `ok`.
4. `scripts/connecta/g0_test_env.sh --apply` → **exit 5**. Subiram containers (`compose up -d --wait`, healthy) e criado o segredo sintético (0600). Falhou em `bundle install` (google-protobuf 3.25.7). Log: `prepare-apply.log`. `db:create`/`db:schema:load` não rodaram por isso.
5. Diagnóstico e correção do toolchain (ver falha 1): `mise uninstall ruby@3.4.4` (somente instalação da tarefa) e reinstalação da mesma versão/fonte com `ac_cv_header_stdbool_h=yes` e `RUBY_BUILD_CACHE_PATH` na pasta da tarefa → exit 0; `HAVE_STDBOOL_H 1` em `config.h`.
6. `gem install bundler -v 2.5.16 --no-document` no prefixo da tarefa → ok.
7. `bundle install` (mesmo ambiente do runner: `RAILS_ENV=test`, alvo G0, `BUNDLE_FROZEN=true`) → exit 0 (2026-10-22T14:52:43Z → 14:53:09Z).
8. `bundle exec rails db:create db:schema:load` (mesmo ambiente; senha lida do arquivo, sem impressão) → exit 0 (14:53:20Z → 14:53:34Z). `db:create` informou "already exists": o Postgres já criara o banco na inicialização do container (`POSTGRES_DB`).
9. `scripts/connecta/g0_test_env.sh --spec` (dry-run) → exit 0; todas as pré-condições `ok`.
10. `scripts/connecta/g0_test_env.sh --spec --apply` (1ª) → **exit 1**: `3 examples, 1 failure` (22 rotas sem classificação; ver `02-inventario-t0-1.md`).
11. Classificação corrigida em `spec/requests/connecta/route_inventory_spec.rb` (sem remover regra nem reduzir cobertura).
12. `scripts/connecta/g0_test_env.sh --spec --apply` (2ª) → exit 0: `Finished in 0.12551 seconds (files took 4.07 seconds to load)`, `3 examples, 0 failures`.
13. Hook de contagem somente leitura (`~/.cache/connecta-g0-test/diag/counts.rb`, fora do repo, via `rspec -r`) → exit 0; números em `02-inventario-t0-1.md`.
14. Guarda, negativa: `bundle exec rspec` com ambiente sem alvo G0 → exit 1, recusa antes do Rails listando as chaves fora do alvo.
15. Guarda, após ajuste de estilo: `bundle exec rspec` com ambiente sem alvo G0 → exit 1, recusa antes do Rails.
16. `bundle exec rubocop` nos dois arquivos Ruby novos (config do repo, sem regra global alterada) → `2 files inspected, no offenses detected`, exit 0.
17. `bash -n scripts/connecta/g0_test_env.sh` → exit 0.
18. Teste de autenticação a partir do host (não de dentro do container): Postgres `127.0.0.1:55432` sem senha → `fe_sendauth: no password supplied` (recusado). Redis `127.0.0.1:56379` sem auth → `NOAUTH Authentication required.` (recusado).
19. Portas publicadas: `docker port` → somente `127.0.0.1:55432` e `127.0.0.1:56379`.

## Falhas encontradas e tratamento

- **Falha 1 — `bundle install` (exit 5).** Causa verificada: o `configure` do Ruby 3.4.4 deste build não detectou `stdbool.h` (`checking for stdbool.h that conforms to C99... no`, no log do ruby-build em `/tmp`). O teste do autoconf usa `#ifndef bool`, que falha no GCC 15 porque o padrão é C23 e `bool` virou palavra-chave. Sem `HAVE_STDBOOL_H`, os headers do Ruby não definem `bool`; gems como `bootsnap` (que acrescenta `-std=c99`) falham com `unknown type name 'bool'`. Probe mínimo confirmou: padrão C23 falha em `#ifndef bool`; `-std=gnu17` passa. Correção: reinstalar a mesma versão/fonte forçando o resultado do teste (`ac_cv_header_stdbool_h=yes`). Não houve fallback para Ruby 4 (o Ruby 4.0.7 do usuário nunca foi usado).
- **Falha 2 — runner não é idempotente após falha parcial.** O `--apply` recusa a reexecução porque o volume já existe e as portas já estão em uso (`scripts/connecta/g0_test_env.sh:175-176`). Os passos restantes (`bundle install`, `db:create db:schema:load`) foram executados à mão, com o mesmo ambiente que o runner exporta. Nenhuma guarda do runner foi enfraquecida. Pendência de decisão no `PROJECT_STATE.md`.
- **Falha 3 — spec 1ª execução: 22 rotas sem classificação.** O inventário estava correto em estrutura, mas faltavam regras para rotas sem controller (montagens) e para as rotas Devise do super admin. Correção: regras adicionais com `arquivo:linha`; nenhuma regra removida.
- **Falha 4 — RuboCop: 2 ofensas** (linha de 166 colunas; módulo aninhado em `g0_target_guard.rb`). Corrigidas (estilo compacto, como exige o `CLAUDE.md`); guarda continua recusando fora do alvo.

## Limitações

- O SHA256 da 1ª instalação não foi verificado (o tarball não ficou retido). A 2ª instalação, da mesma URL e versão, foi verificada.
- O teste de autenticação foi feito do host. Dentro do container, o loopback aceitava conexão sem senha (Postgres) e o `redis-cli` autentica sozinho pelo `REDISCLI_AUTH` do container. Isso não representa a fronteira e não foi usado como prova.
- Não executado: request de runtime para confirmar se as rotas de cadastro/recuperação do super admin respondem sem autenticação (ver `02-inventario-t0-1.md`, seção de riscos).
- Não executado: ESLint (fora do escopo T0.1), shellcheck (não instalado), testes de outras áreas.
- Não executado: T0.2 a T0.7, EVID2..8, WAHA, pareamento, qualquer número de teste.

## Baseline após as alterações

Estado final, `sha256sum -c .context/evidence/g0/00-baseline-sha256.txt` (15:02Z): 10 OK e 6 alterados, todos por desenho e dentro dos donos do briefing:
- código e spec: `spec/requests/connecta/route_inventory_spec.rb` e `spec/support/connecta/g0_target_guard.rb`;
- documentação de estado: `.context/PROJECT_STATE.md`, `.context/REPOMAP.md`, `.context/gotchas.md` e `.context/changelog/CHANGELOG_2026_10_22.md`.

Runner (`scripts/connecta/g0_test_env.sh`), compose (`scripts/connecta/g0-test-services.compose.yml`), `.context/AI-GOVERNANCE.md`, `README.md`, `architecture.md`, `archive/README.md`, `changelog/README.md`, `decisions/` e `plans/README.md` não mudaram. O baseline em `00-baseline-sha256.txt` não é reescrito: ele registra o estado antes desta execução.

## Estado git

- Nenhum arquivo rastreado modificado (`git status --porcelain -uno` vazio). Nenhum commit, push, merge ou PR.
- `Gemfile`, `Gemfile.lock` e `.ruby-version` iguais ao HEAD `7a46faca9`.
- `.bundle/` ignorado (`.gitignore:8`).
