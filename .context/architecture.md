# Arquitetura — chatwootnext

Fronteiras, componentes e decisões técnicas principais. Decisão individual fica em `decisions/`.
Fatos verificados no código; `TODO` = ainda não confirmado.

## Visão geral
Chatwoot (fork `fazer-ai/chatwoot`) em Rails 7.1 com frontend Vue 3 em `app/javascript/`. Overlay Enterprise em `enterprise/`. Jobs assíncronos em Sidekiq (`config/sidekiq.yml`), com PostgreSQL para dados e Redis para Sidekiq e ActionCable (`config/initializers/actioncable.rb`).

## Componentes
| Componente | Pasta | Responsabilidade | Depende de |
|---|---|---|---|
| Backend Rails | `app/`, `config/routes.rb` | Controllers de API (`api/v1`, `api/v2`), models, services | PostgreSQL, Redis |
| Enterprise | `enterprise/` | Extensões por módulo (`prepend_mod_with`), não por edição do OSS (`AGENTS.md`) | `app/` |
| Frontend | `app/javascript/` | SPA Vue (entrypoints: `dashboard.js`, `widget.js`, `portal.js`, etc.) | API REST |
| Jobs | `config/sidekiq.yml`, `app/jobs/` | Processamento assíncrono | Redis, PostgreSQL |
| Banco | `db/` | Migrações (`db/migrate/`) e `db/schema.rb` | PostgreSQL |
| Transferência Connecta | `app/services/connecta/transfer_service.rb` | Transferência atual, mediada (não é a transação local do plano Baileys) | conversas |

## Fronteiras
- Rotas da API de conta ficam em `config/routes.rb` sob `api/v1/accounts/*` e `api/v2/accounts/*`; controllers em `app/controllers/` e, para Enterprise, em `enterprise/app/controllers/`.
- Entrada: strong params (`CLAUDE.md`). Saída: contrato OpenAPI em `swagger/swagger.json`, validado com Skooma nas specs de request (`spec/rails_helper.rb:84-86`).
- Rotas SPA: `/app/*params` cai em `dashboard#index` (`config/routes.rb:20`), antes das rotas explícitas de `/app/...`; ver `gotchas.md`.

## Dados e integrações
- Banco: PostgreSQL configurado por `config/database.yml`, que lê `POSTGRES_*` do ambiente. Migrações em `db/migrate/`, schema em `db/schema.rb`.
- Integrações externas expostas como rotas em `config/routes.rb` (Slack, Shopify, Linear, Notion, Dyte, Twitter, Microsoft, Google, Instagram, TikTok, WhatsApp). Clientes e workers: TODO: mapear por integração.

## Decisões técnicas vigentes
- Assinatura textual de nome — SOMENTE provider Baileys, USER LATEST (2026-10-28, código bold-italic implementado, deploy desta correção pendente): `MessageBuilder` usa `*_Nome_*:` (negrito+itálico WhatsApp) sob `channel_whatsapp_signature_enabled` (ON = auto, OFF = sem append), com upgrade 1x do legado `*Nome*:` do mesmo sender (corpo/histórico intactos) e `_` removido só do nome; `Channel::Api` mantém `*Nome*:` inalterado; WABA/Meta e demais providers mantêm assinatura nativa/custom; exclusões bot/`AgentBot`/relay/privado/inbound/vazio + marker `relay_origin:'bot'` (aviso automático WP); detalhe factual em `.context/changelog/CHANGELOG_2026_10_28.md`; contrato global de autoridade/HMAC em `docs/adr/013-*` (monorepo; "assinatura" RPC ≠ "assinatura" textual).
- Demais decisões em `decisions/` (formato ADR-lite; regra de nomenclatura no `README.md`).
