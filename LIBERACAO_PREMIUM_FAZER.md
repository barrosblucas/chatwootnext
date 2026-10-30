# Liberação Premium — Chatwoot fazer.ai (CE fork)

> **Repo:** `fazer-ai/chatwoot` (Community Edition fork)  
> **Não confundir com:** `fazer-ai/chatwoot-pro` (Kanban + Internal Chat Pro)  
> **Base:** Chatwoot OSS + pasta `enterprise/` + extras BR (Baileys, Z-API, chat interno base, etc.)

## O que este roteiro libera

| Escopo | Liberável neste CE? |
|--------|---------------------|
| Premium Chatwoot Inc. (SLA, audit logs, custom roles, companies, SAML, Captain flags, disable branding, …) | Sim |
| Internal Chat base (canais públicos, DMs, threads) | Já vem no CE (sem flag) |
| Internal Chat Pro (enquetes, canais privados ilimitados, busca sem limite) | Não — só no Pro |
| Kanban de vendas | Não — só paywall neste CE; código no Pro |

## Arquitetura de gating (igual ao Chatwoot original)

1. `ChatwootApp.enterprise?` — pasta `enterprise/` presente  
2. `INSTALLATION_PRICING_PLAN = 'enterprise'` — impede `Internal::ReconcilePlanConfigService` de desligar features  
3. `Account#enable_features!` + `custom_attributes['plan_name'] = 'Enterprise'`

**Diferença neste fork:** `InstallationConfig` usa `value=` (com alias `val=` para compat). Preferir `value=`.

## Setup rápido (dev local já aplicado neste workspace)

```bash
# Postgres com pgvector (porta 5434 neste setup)
docker run -d --name chatwoot_pgvector \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DATABASE=chatwoot_fazer_dev \
  -p 5434:5432 pgvector/pgvector:pg16

# .env já aponta para localhost:5434 / redis localhost:6379
bundle install   # scout_apm >= 5.7.0 (Ruby 3.4)
bundle exec rails db:prepare
bundle exec rails runner script/liberar_premium.rb
```

## Script

Arquivo: `script/liberar_premium.rb`

```bash
bundle exec rails runner script/liberar_premium.rb
```

Ele:

1. Seta `INSTALLATION_PRICING_PLAN=enterprise`  
2. Habilita as features premium listadas em todas as contas  
3. Seta `plan_name=Enterprise`  
4. Se não houver conta, cria SuperAdmin `admin@suaempresa.com` / `Password1!`

## Features premium habilitadas pelo script

```
advanced_assignment, audit_logs, csat_review_notes, companies,
custom_roles, conversation_required_attributes, disable_branding,
sla, saml, custom_tools, captain_integration, captain_integration_v2,
captain_document_auto_sync, channel_voice, advanced_search
```

Notas:

- `advanced_assignment` exige `plan_name` Business/Enterprise  
- `advanced_search` também precisa de `OPENSEARCH_URL`  
- Captain (LLM) precisa de chaves/API configuradas no Super Admin  
- Com `self_hosted_enterprise?`, contas novas já recebem Captain v1/v2 por default

## O que NÃO libera neste CE

- **Kanban** — UI é só paywall (`app/javascript/.../kanban/Index.vue` → https://fazer.ai/kanban)  
- **`internal_chat_pro`** — flag inexistente em `config/features.yml`; `useInternalChatPro()` fica sempre false  

Para esses: clonar/usar `fazer-ai/chatwoot-pro` ou assinar Pro.

## Verificação

```bash
bundle exec rails runner '
  puts ChatwootHub.pricing_plan
  puts ChatwootApp.self_hosted_enterprise?
  Account.find_each { |a| puts "#{a.id}: #{a.custom_attributes["plan_name"]} | #{a.enabled_features.keys.grep(/sla|audit|custom_roles|companies|saml/).join(", ")}" }
'
```

Esperado: `enterprise`, `true`, e as flags premium listadas por conta.
