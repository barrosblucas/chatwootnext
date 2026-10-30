# AI-GOVERNANCE — chatwootnext

Fatos verificados no repositório e regras que ele já declara. A fonte das regras é `AGENTS.md` e `CLAUDE.md` da raiz; este arquivo aponta para elas e não as copia.
Itens em "Propostas sem vigência" não são regra do repo: só valem se o usuário os adotar.

## Stack verificada
- Backend: Ruby 3.4.4 (`.ruby-version`), Rails 7.1.5.2 e rspec-rails 7.0.1 (`Gemfile.lock`).
- Frontend: Vue ^3.5.12, Vite 6.4.2 e Vitest 3.0.5 (`package.json`), pnpm 10.2.0 (`packageManager`).
- Banco: PostgreSQL; `docker-compose.test.yaml:42` usa `pgvector/pgvector:pg16`. Migrações em `db/migrate/`, schema em `db/schema.rb`.
- Contrato de API: `swagger/swagger.json`, validado nas specs de request pelo Skooma (`spec/rails_helper.rb:84-86`).
- Ambiente de teste: `config/cable.yml:12-13` usa adapter `test`; `config/initializers/01_redis.rb:10` usa `MockRedis` quando `Rails.env.test?`.

## Comandos que existem (não são gates obrigatórios por este arquivo)
- Lint Ruby: `bundle exec rubocop -a` (`AGENTS.md:13`).
- Lint JS/Vue: `pnpm eslint` (`CLAUDE.md`, Build/Test/Lint).
- Testes Ruby: `bundle exec rspec <arquivo>` (`AGENTS.md`).
- Testes JS: `pnpm test` (`package.json:8`, Vitest).
- Build e checagem de tipos: não há script verificado no `package.json` (TODO).

## Regras declaradas no repo (fonte entre parênteses)
- Enterprise estende o OSS por `prepend_mod_with`/`include_mod_with`, sem editar arquivo OSS para comportamento só de Enterprise (`CLAUDE.md`, Enterprise Edition Notes; `AGENTS.md:141`).
- Specs para novas funcionalidades cobrindo fluxo principal e casos de erro/limite relevantes; regressão para bugfix não trivial (`AGENTS.md:55`).
- Strong params no Rails; models com validação de presença/unicidade e índices (`CLAUDE.md`, Code Style e General Guidelines).
- RuboCop com linha máxima de 150 caracteres (`CLAUDE.md`, Code Style).
- Estilo visual só com classes Tailwind, sem CSS customizado nem estilo inline (`CLAUDE.md`, Styling).
- Traduções: `en.yml`/`en.json` e `pt_BR.yml`/`pt_BR.json` (`CLAUDE.md`, Project-Specific).
- Novos toggles de conta: preferir `settings` (jsonb) a `feature_flags` (`CLAUDE.md`, Account-level toggles).

## Propostas sem vigência
Vieram de templates ou de suposições do contexto e não têm fonte no repo. Não aplicar como regra.
- Taxonomia de mudança (`regra_de_negocio`, `borda_externa`, `mudanca_mecanica`): sem fonte em `AGENTS.md` ou `CLAUDE.md`.
- "Função nova sem teste bloqueia a conclusão": `AGENTS.md:55` pede specs, sem exigir bloqueio formal.
- "Definition of Done" de 4 itens: sem fonte no repo.
- "Logs não expõem dados pessoais": não declarado em `AGENTS.md` nem `CLAUDE.md`.
- "Segredos não são hardcoded": não declarado. Contradito por `config/database.yml:32`, que usa `chatwoot_prod` como senha padrão no ambiente production.
- Política de exceções de teste e checagem de tipos: `TODO: confirmar com o usuário`.

## Contexto
- Regras de desenvolvimento: `AGENTS.md` e `CLAUDE.md` da raiz.
- Este `.context/` registra fatos; quando o código divergir de um documento, o código vale e a divergência vai para `gotchas.md` ou `PROJECT_STATE.md`.
