# REPOMAP — chatwootnext

Mapa real da estrutura de pastas. Atualize quando pastas forem criadas, removidas ou mudarem de responsabilidade.
Criado em 2026-10-22 a partir do repositório.

## Árvore (níveis principais)
```
app/  bin/  clevercloud/  config/  db/  deployment/  docker/  e2e/  enterprise/
lib/  log/  public/  rubocop/  script/  spec/  swagger/  tests/  theme/  tmp/  vendor/
scripts/connecta/   (novo em 2026-10-22: preparo do ambiente de teste G0)
.context/           (este contexto)
```

## Responsabilidades
| Pasta | Responsabilidade | Observação |
|---|---|---|
| `app/` | Rails: controllers, models, services, jobs, `javascript/` (frontend Vue) | `app/services/connecta/` = transferência atual |
| `config/` | Rotas (`routes.rb`), `database.yml`, `sidekiq.yml`, initializers | |
| `db/` | Migrações (`db/migrate/`, 185 arquivos) e `schema.rb` | |
| `enterprise/` | Overlay Enterprise (estende OSS por módulos) | `AGENTS.md` |
| `spec/` | RSpec | `spec/requests/connecta/` (inventário de rotas, executado em 2026-10-22: 3 exemplos, 0 falhas; 877 rotas, 0 não classificadas); `spec/support/connecta/g0_target_guard.rb` é carregada pelo suporte geral de `spec/rails_helper.rb:34` (só define métodos); só a execução `verify!` é específica de `route_inventory_spec.rb` |
| `swagger/` | OpenAPI (`swagger.json`) | validado com Skooma |
| `docker/` | Dockerfile e entrypoints | |
| `e2e/` | Testes end-to-end (`helpers/`, `internal-chat/`) | |
| `tests/` | Testes Playwright (`tests/playwright/`) | |
| `scripts/connecta/` | Runner (`g0_test_env.sh`) e compose (`g0-test-services.compose.yml`) do ambiente de teste G0 | dry-run por padrão; `--apply`, `--spec` e `--teardown` exigem autorização |
| `.context/evidence/g0/` | Evidências do G0: baseline por SHA256 (`00`), execução e validação (`01`), inventário T0.1 (`02`), retomada do runner (`03-retomada-*`, com cópias e logs) e testes stub (`04`) | novo em 2026-10-22 |
| `.bundle/gems/` | Gems do ambiente G0 (`BUNDLE_PATH`), gerado pelo `bundle install` | ignorado pelo git (`.gitignore:8`); não versionar |
| `theme/` | Tema visual (ex.: `colors.js`, `icons.js`) | |
| `bin/`, `script/`, `lib/`, `public/`, `rubocop/`, `deployment/`, `clevercloud/`, `vendor/`, `__mocks__/` | TODO: confirmar responsabilidade de cada pasta | |

## Pontos de entrada
- `config.ru` (Rack); `config/routes.rb` (rotas).
- `Procfile.dev` (processos de desenvolvimento).
- Frontend: `app/javascript/entrypoints/` (`dashboard.js`, `widget.js`, `portal.js`, `survey.js`, `sdk.js`, `superadmin.js`, `v3app.js`).

## Testes e scripts
- Ruby: `bundle exec rspec <arquivo>` (`AGENTS.md`).
- JS: `pnpm test` (`package.json`, Vitest via `vitest.config.ts`); `pnpm eslint`.
- G0: `scripts/connecta/g0_test_env.sh` (dry-run; `--apply` exige autorização). Spec: `scripts/connecta/g0_test_env.sh --spec --apply` (executada em 2026-10-22: 3 exemplos, 0 falhas; ver `.context/evidence/g0/01` e `02`).
