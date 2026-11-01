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
| `app/services/connecta/scope/` | Spike G0 de escopo (T0.2 partes A e B1): modelos `connecta_g0_*`, projeção, gate, query e hooks prepended (HTTP de conversa e mensagens em `conversation_http_hook.rb`) | não é produto; `installer.rb` só é chamado pelo spec G0 |
| `config/` | Rotas (`routes.rb`), `database.yml`, `sidekiq.yml`, initializers | |
| `db/` | Migrações (`db/migrate/`, 185 arquivos) e `schema.rb` | |
| `enterprise/` | Overlay Enterprise (estende OSS por módulos) | `AGENTS.md` |
| `spec/` | RSpec | `spec/connecta/` (T0.4 anexos e T0.5 AgentBot, executadas em 2026-10-22: 29 exemplos, 0 falhas); `spec/requests/connecta/` (inventário de rotas, executado em 2026-10-22: 3 exemplos, 0 falhas; 877 rotas, 0 não classificadas); `spec/support/connecta/g0_target_guard.rb` é carregada pelo suporte geral de `spec/rails_helper.rb:34` (só define métodos); só a execução `verify!` é específica de `route_inventory_spec.rb` |
| `swagger/` | OpenAPI (`swagger.json`) | validado com Skooma |
| `docker/` | Dockerfile e entrypoints | |
| `e2e/` | Testes end-to-end (`helpers/`, `internal-chat/`) | |
| `tests/` | Testes Playwright (`tests/playwright/`) | |
| `scripts/connecta/` | Runner (`g0_test_env.sh`) e compose (`g0-test-services.compose.yml`) do ambiente de teste G0 | dry-run por padrão; `--apply`, `--spec` e `--teardown` exigem autorização |
| `docker-compose.teste-lan.baileys-override.yml` (raiz) | Override de TESTE: liga Rails/Sidekiq do `docker-compose.teste-lan.yml` à rede edge do Baileys de teste + env `BAILEYS_PROVIDER_*` (chave via interpolação, sem literal) e entrypoint do Rails sem `db:chatwoot_prepare` | runtime Baileys+segredos em `/tmp/opencode/chatwootnext-baileys-runtime/` (privado, fora do Git) |
| `docker-compose.teste-lan.human-number-override.yml` (raiz) | Override TESTE human-number Saude por unidades: `CONNECTA_HUMAN_NUMBER_ENABLED=true`, `CONNECTA_ACCOUNT_ID=2`, `CONNECTA_PLATFORM_URL` local, `CONNECTA_RECEPTION_ORG_UNIT_ID` + `CONNECTA_*_SECRET` via interpolação `${...:?}` (sem literal); uso com os 2 composes acima | segredos em memória a partir de `.../secrets/connecta-hmac.secrets` (0600), nunca no repo |
| `.context/evidence/g0/` | Evidências do G0: baseline por SHA256 (`00`), execução e validação (`01`), inventário T0.1 (`02`), retomada do runner (`03-retomada-*`, com cópias e logs), testes stub (`04`) e medições T0.4/T0.5 (`05-*`: EVID4, EVID6, baseline e logs), recuperação do lote B2 (`08-recuperacao-b2.md`, com logs em `08-logs/`) | novo em 2026-10-22 |
| `spec/connecta/support/` | Helpers do spike G0 (`g0_scope_schema.rb`: schema create-only, fora do carregamento automático de `rails_helper`; `g0_scope_fixture.rb`: fixture compartilhado dos specs de escopo) | carregado por `require_relative` no spec de escopo |
| `.bundle/gems/` | Gems do ambiente G0 (`BUNDLE_PATH`), gerado pelo `bundle install` | ignorado pelo git (`.gitignore:8`); não versionar |
| `theme/` | Tema visual (ex.: `colors.js`, `icons.js`) | |
| `bin/`, `script/`, `lib/`, `public/`, `rubocop/`, `deployment/`, `clevercloud/`, `vendor/`, `__mocks__/` | TODO: confirmar responsabilidade de cada pasta | |

## Entradas locais do snapshot C (F2, WIP não homologado)
- `app/services/connecta/scope/native_admin.rb`: associação atual de administrador da conta do recurso; usada nos hooks/gates existentes.
- `app/services/connecta/scope/conversation_reuse.rb` e `app/services/connecta/runtime/reception_scope_creator.rb`: reuso/recepção do working tree C, WIP; sem regenerar banco nesta integração.
- `app/controllers/api/v1/accounts/conversations/connecta_manual_admissions_controller.rb` e `app/services/connecta/runtime/manual_admission_transaction.rb`: endpoint/transação de admissão manual, WIP.
- `app/javascript/dashboard/components-next/NewConversation/components/ConnectaSectorPicker.vue`: componente incluído mas ainda não conectado ao template do compose no snapshot; não declara fluxo pronto.

## Pontos de entrada
- `config.ru` (Rack); `config/routes.rb` (rotas).
- `Procfile.dev` (processos de desenvolvimento).
- Frontend: `app/javascript/entrypoints/` (`dashboard.js`, `widget.js`, `portal.js`, `survey.js`, `sdk.js`, `superadmin.js`, `v3app.js`).

## Testes e scripts
- Ruby: `bundle exec rspec <arquivo>` (`AGENTS.md`).
- JS: `pnpm test` (`package.json`, Vitest via `vitest.config.ts`); `pnpm eslint`.
- G0: `scripts/connecta/g0_test_env.sh` (dry-run; `--apply` exige autorização). Spec: `scripts/connecta/g0_test_env.sh --spec --apply` (executada em 2026-10-22: 3 exemplos, 0 falhas; ver `.context/evidence/g0/01` e `02`).
