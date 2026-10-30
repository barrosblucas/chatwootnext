# Roteiro Completo: Liberação de Features Premium no Chatwoot Self-Hosted

> **Versão:** Chatwoot v4.x (commit master, sem tags)
> **Ruby:** 3.4.4 | **Rails:** 7.1.5.2 | **Node:** 24.x | **PostgreSQL:** 16 (pgvector)
> **Ambiente:** Linux (Ubuntu/Debian), self-hosted, desenvolvimento

---

## Contexto e Arquitetura do Sistema de Gating

O Chatwoot tem **3 camadas de verificação** que bloqueiam features premium:

### Camada 1: Detecção de Enterprise (`ChatwootApp.enterprise?`)
- Arquivo: `lib/chatwoot_app.rb`
- Verifica se o diretório `enterprise/` existe no projeto
- Retorna `true` automaticamente quando o código enterprise está presente

### Camada 2: Plano de Precificação (`ChatwootHub.pricing_plan`)
- Arquivo: `lib/chatwoot_hub.rb`
- Lê `InstallationConfig` onde `name = 'INSTALLATION_PRICING_PLAN'`
- Default: `'community'`
- Se `'community'`, o `ReconcilePlanConfigService` desativa features premium periodicamente

### Camada 3: Feature Flags por Account (`Account.feature_enabled?`)
- Arquivo: `app/models/concerns/featurable.rb`
- Usa gem `FlagShihTzu` com bitmask nas colunas `feature_flags` (bigint) e `feature_flags_ext_1`
- Cada feature = 1 bit na coluna
- Método: `account.feature_enabled?('feature_name')`

### O que bloqueia tudo: `Internal::ReconcilePlanConfigService`
- Arquivo: `enterprise/app/services/internal/reconcile_plan_config_service.rb`
- Roda periodicamente via `Internal::CheckNewVersionsJob`
- Se `pricing_plan == 'community'`:
  1. Desativa features listadas em `enterprise/config/premium_features.yml` em TODAS as contas
  2. Reseta configs de branding

### Lista de features em `enterprise/config/premium_features.yml`:
```yaml
- disable_branding
- audit_logs
- custom_roles
- captain_integration
- captain_integration_v2
- captain_document_auto_sync
- csat_review_notes
- conversation_required_attributes
```

### Features liberadas (7, sem dependência externa):
| Feature | Descrição |
|---------|-----------|
| `advanced_assignment` | Atribuição inteligente (round-robin/balanced) |
| `audit_logs` | Logs de auditoria |
| `csat_review_notes` | Notas em avaliações CSAT |
| `companies` | CRM de empresas (B2B) |
| `custom_roles` | Funções personalizadas |
| `conversation_required_attributes` | Campos obrigatórios em conversas |
| `disable_branding` | Remove marca Chatwoot |

---

## PRÉ-REQUISITOS

### Variáveis de ambiente necessárias
```bash
export POSTGRES_PASSWORD=postgres
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export RAILS_ENV=development
export DISABLE_MINI_PROFILER=true   # evita bug Rack::File no Ruby 3.4
```

### Serviços necessários
- PostgreSQL 16+ com extensões `pgcrypto`, `pg_trgm`, `vector`
- Redis (porta 6379)
- Node.js 24+ com pnpm
- Ruby 3.4.4 com rbenv + bundler

---

## PASSO 1: Configurar PostgreSQL com pgvector

### 1.1 Iniciar PostgreSQL em Docker (com pgvector)
```bash
docker run -d \
  --name chatwoot_pg \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=chatwoot_dev \
  -p 5432:5432 \
  pgvector/pgvector:pg16
```

### 1.2 Aguardar inicialização
```bash
sleep 10
PGPASSWORD=postgres psql -h localhost -U postgres -c "SELECT 1"
```

### 1.3 Se houver PostgreSQL do sistema rodando na porta 5432, pará-lo primeiro
```bash
# Via Docker privilegiado (se não tiver sudo)
docker run --rm --pid=host --privileged alpine:3.19 \
  sh -c "kill $(pgrep -f 'postgres -D /var/lib/postgresql')"
sleep 3
```

---

## PASSO 2: Instalar Dependências

### 2.1 Gems Ruby
```bash
cd /home/thanos/chatwoot_atende
bundle install
```

### 2.2 Pacotes Node
```bash
pnpm install
```

### 2.3 Se o `scout_apm` falhar ao compilar (Ruby 3.4)
```bash
# Editar Gemfile, trocar:
#   gem 'scout_apm', require: false
# por:
#   gem 'scout_apm', '>= 5.3.3', require: false
# Depois:
bundle update scout_apm --conservative
```

---

## PASSO 3: Criar Banco e Carregar Schema

### 3.1 Criar banco de dados
```bash
POSTGRES_PASSWORD=postgres bundle exec rails db:create
```

### 3.2 Carregar schema completo (cria todas as 97 tabelas)
```bash
POSTGRES_PASSWORD=postgres bundle exec rails db:schema:load
```

### 3.3 Verificar contagem de tabelas (deve ser ~97)
```bash
PGPASSWORD=postgres psql -h localhost -U postgres -d chatwoot_dev -t -c \
  "SELECT count(*) FROM pg_tables WHERE schemaname='public';"
```

---

## PASSO 4: Aplicar Configurações de Plano Enterprise

### 4.1 Setar `INSTALLATION_PRICING_PLAN` para `'enterprise'`
```bash
POSTGRES_PASSWORD=postgres bundle exec rails runner '
  ic = InstallationConfig.find_or_initialize_by(name: "INSTALLATION_PRICING_PLAN")
  ic.value = "enterprise"
  ic.locked = true
  ic.save!
  puts "INSTALLATION_PRICING_PLAN = enterprise"
'
```

### 4.2 Habilitar criação de múltiplas contas
```bash
POSTGRES_PASSWORD=postgres bundle exec rails runner '
  ac = InstallationConfig.find_or_initialize_by(name: "CREATE_NEW_ACCOUNT_FROM_DASHBOARD")
  ac.value = true
  ac.locked = false
  ac.save!
  puts "CREATE_NEW_ACCOUNT_FROM_DASHBOARD = true"
'
```

### 4.3 Verificar
```bash
POSTGRES_PASSWORD=postgres bundle exec rails runner '
  puts "Pricing plan: #{ChatwootHub.pricing_plan}"
  puts "Self-hosted enterprise: #{ChatwootApp.self_hosted_enterprise?}"
'
# Deve imprimir: "enterprise" e "true"
```

---

## PASSO 5: Criar Conta, Usuário Admin e Habilitar Features

### Script Ruby completo (`setup_premium.rb`):
```ruby
require 'bcrypt'

# 1. Criar conta
account = Account.create!(name: 'Sua Empresa')

# 2. Criar SuperAdmin
user = User.new(
  name: 'Admin',
  email: 'admin@suaempresa.com',
  password: 'Password1!',
  type: 'SuperAdmin'
)
user.skip_confirmation!
user.save!

# 3. Vincular usuário à conta
AccountUser.create!(
  account_id: account.id,
  user_id: user.id,
  role: :administrator
)

# 4. Criar inbox (Web Widget)
web_widget = Channel::WebWidget.create!(
  account: account,
  website_url: 'https://suaempresa.com'
)
inbox = Inbox.create!(
  channel: web_widget,
  account: account,
  name: 'Atendimento'
)
InboxMember.create!(user: user, inbox: inbox)

# 5. Habilitar as 7 features premium
account.enable_features!(
  'advanced_assignment',
  'audit_logs',
  'csat_review_notes',
  'companies',
  'custom_roles',
  'conversation_required_attributes',
  'disable_branding'
)

# 6. Setar plan_name (necessário para advanced_assignment e companies)
account.custom_attributes['plan_name'] = 'Enterprise'
account.save!

puts "Conta criada: #{account.id} (#{account.name})"
puts "Features habilitadas: #{account.enabled_features.keys.sort.join(', ')}"
puts "Login: #{user.email} / Password1!"
```

### Executar:
```bash
POSTGRES_PASSWORD=postgres bundle exec rails runner setup_premium.rb
```

### Para aplicar em TODAS as contas existentes:
```ruby
Account.all.each do |a|
  a.enable_features!(
    'advanced_assignment', 'audit_logs', 'csat_review_notes',
    'companies', 'custom_roles', 'conversation_required_attributes',
    'disable_branding'
  )
  a.custom_attributes['plan_name'] = 'Enterprise'
  a.save!
  puts "Conta #{a.id} (#{a.name}): features habilitadas"
end
```

---

## PASSO 6: Habilitar Features em Novas Contas (Automático)

### 6.1 Criar initializer para auto-habilitar features em novas contas
```bash
cat > config/initializers/auto_enable_premium.rb << 'RUBY'
# Auto-habilitar features premium em novas contas (self-hosted enterprise)
Rails.application.config.after_initialize do
  if ChatwootApp.self_hosted_enterprise?
    Account.after_create do |account|
      premium_features = %w[
        advanced_assignment
        audit_logs
        csat_review_notes
        companies
        custom_roles
        conversation_required_attributes
        disable_branding
      ]
      account.enable_features!(*premium_features)
      account.custom_attributes['plan_name'] = 'Enterprise'
      account.save!
    end
  end
end
RUBY
```

### 6.2 Para contas criadas via SuperAdmin UI
As features também podem ser habilitadas manualmente:
- Acessar: `http://localhost:3001/super_admin/accounts/:id`
- Na seção "Features", marcar as checkboxes premium
- **Nota:** As checkboxes premium só ficam habilitadas se `INSTALLATION_PRICING_PLAN != 'community'`

---

## PASSO 7: Aumentar Limite de inotify (necessário para Vite/Rails)

```bash
# Via Docker privilegiado (se não tiver permissão direta)
docker run --rm --privileged alpine:3.19 \
  sh -c "echo 262144 > /proc/sys/fs/inotify/max_user_watches"
```

---

## PASSO 8: Iniciar Serviços

### 8.1 Iniciar Puma (backend Rails)
```bash
# Limpar PID files stale
rm -f tmp/pids/server.pid
rm -rf tmp/cache

# Iniciar via screen (sobrevive ao fechamento do terminal)
screen -dmS puma bash -c \
  'cd /home/thanos/chatwoot_atende && \
   POSTGRES_PASSWORD=postgres \
   DISABLE_MINI_PROFILER=true \
   bundle exec puma -C config/puma.rb -p 3001 -b tcp://0.0.0.0 \
   > /tmp/puma.log 2>&1'

# Aguardar inicialização (~15 segundos)
sleep 15

# Verificar
curl -s -o /dev/null -w "Puma: %{http_code}\n" http://localhost:3001/
# Deve retornar: Puma: 200
```

### 8.2 Iniciar Vite (frontend dev server)
```bash
# Configurar Vite para aceitar conexões externas
# Editar config/vite.json e adicionar "host": "0.0.0.0" na seção development:
# {
#   "development": {
#     "autoBuild": true,
#     "publicOutputDir": "vite-dev",
#     "host": "0.0.0.0",
#     "port": 3036
#   }
# }

# Instalar postcss-import se faltar
pnpm add -D postcss-import

# Script de inicialização do Vite
cat > /tmp/start_vite.sh << 'BASH'
#!/bin/bash
export PATH="/home/thanos/.nvm/versions/node/v24.13.0/bin:$PATH"
cd /home/thanos/chatwoot_atende
VITE_BIN=$(ls node_modules/.pnpm/vite@*/node_modules/vite/bin/vite.js)
exec node "$VITE_BIN" --host 0.0.0.0 --port 3036
BASH
chmod +x /tmp/start_vite.sh

# Iniciar via screen
screen -dmS vite /tmp/start_vite.sh
sleep 12

# Verificar
curl -s -o /dev/null -w "Vite: %{http_code}\n" \
  http://localhost:3036/vite-dev/entrypoints/dashboard.js
# Deve retornar: Vite: 200
```

### 8.3 Iniciar Sidekiq (background jobs)
```bash
screen -dmS sidekiq bash -c \
  'cd /home/thanos/chatwoot_atende && \
   POSTGRES_PASSWORD=postgres \
   bundle exec sidekiq -C config/sidekiq.yml \
   > /tmp/sidekiq.log 2>&1'
sleep 10

# Verificar
ps aux | grep sidekiq | grep -v grep | head -1
```

---

## PASSO 9: Verificação Final

### Script de verificação completo:
```bash
echo "============================================"
echo "  VERIFICAÇÃO COMPLETA"
echo "============================================"

echo ""
echo "1. PREÇO/PLANO:"
POSTGRES_PASSWORD=postgres bundle exec rails runner '
  puts "   Pricing plan: #{ChatwootHub.pricing_plan}"
  puts "   Enterprise: #{ChatwootApp.enterprise?}"
  puts "   Self-hosted enterprise: #{ChatwootApp.self_hosted_enterprise?}"
' 2>/dev/null

echo ""
echo "2. CONTAS E FEATURES:"
PGPASSWORD=postgres psql -h localhost -U postgres -d chatwoot_dev -c \
  "SELECT id, name, custom_attributes->>'plan_name' as plan FROM accounts;"

echo ""
echo "3. SERVIÇOS:"
echo "   Puma: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/ 2>/dev/null)"
echo "   Vite: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3036/vite-dev/entrypoints/dashboard.js 2>/dev/null)"

echo ""
echo "4. LOGIN:"
echo "   URL: http://<IP>:3001"
echo "   Email: admin@suaempresa.com"
echo "   Senha: Password1!"

echo ""
echo "============================================"
```

---

## ARQUIVOS MODIFICADOS (Resumo)

| Arquivo | Modificação | Motivo |
|---------|-------------|--------|
| `Gemfile` | `scout_apm` versão `>= 5.3.3` | Compatibilidade Ruby 3.4.4 |
| `config/vite.json` | Adicionado `"host": "0.0.0.0"` | Acesso externo via IP |
| `config/boot.rb` | Nenhuma (mantido bootsnap) | — |
| `config/environments/development.rb` | Nenhuma (mantido EventedFileUpdateChecker) | — |

### Arquivos temporários criados (não persistir):
- `/tmp/start_vite.sh` — Script de inicialização do Vite
- `/tmp/setup_premium.rb` — Script de setup de dados
- `/tmp/full_setup.rb` — Setup completo

---

## BANCO DE DADOS (Comandos Diretos SQL)

### Verificar bitmask de features premium:
```sql
-- As features são armazenadas como bitmask na coluna feature_flags (bigint)
-- Bit position = índice da feature no array de config/features.yml

-- Verificar features ativas:
SELECT id, name, feature_flags, 
       custom_attributes->>'plan_name' as plan
FROM accounts;
```

### Habilitar features via SQL direto (sem ActiveRecord):
```ruby
# Calcular bitmask
features = YAML.safe_load(File.read('config/features.yml')).map { |f| f['name'] }
premium = %w[advanced_assignment audit_logs csat_review_notes companies 
             custom_roles conversation_required_attributes disable_branding]
bitmask = premium.sum { |f| (idx = features.index(f)) ? (1 << idx) : 0 }

# Aplicar via SQL
ActiveRecord::Base.connection.execute(
  "UPDATE accounts SET feature_flags = #{bitmask}, 
   custom_attributes = COALESCE(custom_attributes, '{}'::jsonb) || 
   '{\"plan_name\": \"Enterprise\"}'::jsonb;"
)
```

### Setar plano enterprise via SQL (formato YAML string dentro de jsonb):
```sql
-- IMPORTANTE: serialized_value é jsonb mas o Rails serializa com YAML
-- Deve ser uma STRING YAML, não JSON. Usar to_jsonb para converter:
UPDATE installation_configs
SET serialized_value = to_jsonb(
  '--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess
  value: enterprise
  '::text
)
WHERE name = 'INSTALLATION_PRICING_PLAN';
```

---

## PROBLEMAS CONHECIDOS E SOLUÇÕES

### 1. `NameError: uninitialized constant Rack::File`
**Causa:** `rack-mini-profiler` incompatível com Ruby 3.4 + Rack 3
**Solução:** Variável de ambiente `DISABLE_MINI_PROFILER=true`

### 2. `Listen::Error::INotifyMaxWatchesExceeded`
**Causa:** Limite de inotify watchers do kernel
**Solução:** `echo 262144 > /proc/sys/fs/inotify/max_user_watches`

### 3. `TypeError: no implicit conversion of Array into String` (Psych/YAML)
**Causa:** `InstallationConfig.serialized_value` armazenada em formato JSON em vez de YAML string
**Solução:** Sempre usar o modelo Rails (`ic.value = 'enterprise'`), NUNCA SQL direto com jsonb

### 4. `Cannot find module 'postcss-import'`
**Causa:** Pacote npm faltante
**Solução:** `pnpm add -D postcss-import`

### 5. `PG::UndefinedTable: relation "user_sessions" does not exist`
**Causa:** Schema incompleto (dump/restore parcial)
**Solução:** Recriar banco com `db:schema:load` (não usar dump/restore entre versões PG)

### 6. `extension "vector" is not available`
**Causa:** PostgreSQL sem pgvector
**Solução:** Usar imagem Docker `pgvector/pgvector:pg16`

### 7. Puma morre ao fechar terminal/shell
**Causa:** SIGHUP enviado ao processo quando shell termina
**Solução:** Usar `screen -dmS` para iniciar processos

### 8. `NoMethodError: undefined method 'mfa_enabled?'`
**Causa:** Colunas de MFA/OTP não existem na tabela users
**Solução:** Garantir que migração `add_two_factor_to_users` foi aplicada via `db:schema:load`

---

## COMANDOS PARA GERENCIAR SERVIÇOS

### Iniciar tudo:
```bash
#!/bin/bash
cd /home/thanos/chatwoot_atende
rm -f tmp/pids/server.pid && rm -rf tmp/cache

screen -dmS puma bash -c \
  'cd /home/thanos/chatwoot_atende && POSTGRES_PASSWORD=postgres DISABLE_MINI_PROFILER=true bundle exec puma -C config/puma.rb -p 3001 -b tcp://0.0.0.0 > /tmp/puma.log 2>&1'

screen -dmS vite /tmp/start_vite.sh

screen -dmS sidekiq bash -c \
  'cd /home/thanos/chatwoot_atende && POSTGRES_PASSWORD=postgres bundle exec sidekiq -C config/sidekiq.yml > /tmp/sidekiq.log 2>&1'

echo "Aguardando inicialização..."
sleep 20
echo "Puma: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/ 2>/dev/null)"
echo "Vite: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3036/vite-dev/entrypoints/dashboard.js 2>/dev/null)"
```

### Parar tudo:
```bash
screen -S puma -X quit
screen -S vite -X quit
screen -S sidekiq -X quit
pkill -f "puma.*chatwoot"
pkill -f "vite.*chatwoot"
pkill -f "sidekiq.*chatwoot"
```

### Ver status:
```bash
screen -ls
ps aux | grep -E "puma.*chatwoot|node.*vite|sidekiq.*chatwoot" | grep -v grep
curl -s -o /dev/null -w "Puma: %{http_code}\n" http://localhost:3001/
```

---

## CONFIGURAÇÃO DE REDE (Acesso Externo)

### Habilitar acesso via IP da rede local:
1. **Puma:** Já binde em `0.0.0.0` (aceita qualquer IP)
2. **Vite:** Editar `config/vite.json`:
   ```json
   {
     "development": {
       "host": "0.0.0.0",
       "port": 3036
     }
   }
   ```
3. **Acesso:** `http://<IP_DA_MAQUINA>:3001`

---

## FLUXO LÓGICO DA LIBERAÇÃO (Diagrama)

```
┌─────────────────────────────────────────────────────────────────┐
│                    LIBERAÇÃO DE FEATURES PREMIUM                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. INSTALLATION_PRICING_PLAN = 'enterprise'                    │
│     └─→ Impede ReconcilePlanConfigService de desativar features │
│                                                                  │
│  2. ChatwootApp.self_hosted_enterprise? = true                  │
│     └─→ enterprise? (dir existe) + plan='enterprise'            │
│                                                                  │
│  3. Account.feature_flags (bitmask) = features ativadas         │
│     └─→ Bit 1: advanced_assignment                              │
│     └─→ Bit 2: audit_logs                                       │
│     └─→ Bit 3: csat_review_notes                                │
│     └─→ Bit 4: companies                                        │
│     └─→ Bit 5: custom_roles                                     │
│     └─→ Bit 6: conversation_required_attributes                 │
│     └─→ Bit 7: disable_branding                                 │
│                                                                  │
│  4. Account.custom_attributes.plan_name = 'Enterprise'          │
│     └─→ Necessário para business_or_enterprise_plan? check      │
│                                                                  │
│  RESULTADO:                                                      │
│  ✅ Features aparecem na UI (sem paywall)                       │
│  ✅ Controllers enterprise respondem (não 404)                  │
│  ✅ ReconcilePlanConfigService não desativa mais nada           │
│  ✅ SuperAdmin permite editar checkboxes premium                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```
