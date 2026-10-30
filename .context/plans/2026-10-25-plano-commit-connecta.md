# Plano de commit — fork Chatwootnext (Connecta G0/F7)

Data: 2026-10-25 · Frente: FORK-c9 · Status: **somente plano. Nenhum `git add` ou `git commit` foi executado.** O humano revisa antes.

## 1. Estado do repo

- Caminho: `/home/thanos/chatwootnext-connecta-g0-prep`
- Branch: `feat/connecta-g0-prep`
- HEAD: `7a46faca9`
- `git status --porcelain -uall`: **329 caminhos** (309 não rastreados `??`, 20 modificados ` M`).
- Nada commitado nesta frente.

## 2. Divisão proposta em commits

| # | Commit | Caminhos | Qtd |
|---|---|---|---|
| c1 | Tabelas, modelos e migrações do número humano | `db/migrate/20261024*`, `db/schema.rb`, `app/models/connecta/*` | 14 |
| c2 | Runtime, ACL, escopo e contrato v1 (inclui transferência) | `app/services/connecta/**`, `app/jobs/connecta/**`, `app/controllers/**` (Connecta), `app/channels`, `config/routes.rb`, `config/initializers/connecta_runtime.rb`, `spec/connecta/**`, `spec/requests/connecta/**`, `spec/support/connecta/**` | 135 |
| c3 | UI (dashboard Vue/JS) | `app/javascript/**`, `app/views/layouts/vueapp.html.erb`, `app/controllers/dashboard_controller.rb` | 22 |
| c4 | F7 deploy e runbooks | `deploy/baileys-api/**`, `docs/runbooks/*` | 7 |
| c5 | Scripts de teste G0 | `scripts/connecta/*` | 2 |
| c6 | Contexto do projeto (`.context`, sem evidências) | `.context/*` exceto `.context/evidence/**` | 21 |
| c7 | Evidências G0 | `.context/evidence/**` | 128 |

Soma: 14 + 135 + 22 + 7 + 2 + 21 + 128 = **329** (conferido: sem duplicados, sem caminho com espaço).

### Restrição de acoplamento (importante para a ordem)

`app/services/connecta/runtime/installer.rb` faz `prepend` de `Connecta::Transfer::*` no boot (linhas 17–21), e `g0_adapter.rb` referencia `Connecta::Transfer::TransferRecord`. Por isso **runtime (c2) e transferência não podem ser commits separados**: um commit só com runtime quebraria o boot. Transferência fica dentro de c2. c1 precisa vir antes de c2 porque os modelos e o schema são usados por ambos.

## 3. Mensagens sugeridas (Conventional Commits, em português, como o histórico)

- **c1** `feat(connecta): adiciona tabelas e modelos do número humano`
- **c2** `feat(connecta): runtime de ACL, escopo e transferência com contrato v1`
- **c3** `feat(connecta): interface de transferência e configurações no dashboard`
- **c4** `chore(connecta): manifesto baileys-api e runbooks de saúde e contingência`
- **c5** `test(connecta): scripts de ambiente de teste G0`
- **c6** `docs(connecta): contexto do projeto, decisões e changelog`
- **c7** `docs(connecta): evidências das frentes G0 e F3–F7`

## 4. Arquivos que exigem atenção

- **`db/schema.rb`** (c1): gerado. Muda a versão de `2026_07_18_000000` para `2026_10_24_000001` e adiciona 10 tabelas `connecta_*`. Deve ser commitado junto com as duas migrações; não editar à mão.
- **`config/routes.rb`** (c2): compartilhado com o app base. Diff só acrescenta rotas `connecta`. Revisar antes para não levar rota de outra frente.
- **`app/controllers/dashboard_controller.rb`** e **`app/views/layouts/vueapp.html.erb`** (c3): compartilhados com o dashboard. Diff pequeno.
- **`app/channels/application_cable/connection.rb`** (c2): compartilhado. Diff de 7 linhas.
- **`.context/**`** (c6, c7): documentação. A evidência (c7) é volumosa e separada de propósito.
- **`.context/changelog/CHANGELOG_2026_10_25.md`** e **`.context/gotchas.md`**: arquivos desta frente. Podem estar nos dois commits c6 e c7 se o humano escolher outra separação.

## 5. Confirmação de isolamento

- Nenhum `.env` e nenhum arquivo real de segredo na lista. O único `.env*` é `deploy/baileys-api/.env.example` (placeholders).
- Varredura de chaves privadas e tokens (AKIA, sk-, PRIVATE KEY) nos caminhos listados: nada encontrado.
- Compose de teste (`scripts/connecta/g0-test-services.compose.yml`) publica só em `127.0.0.1`.
- Caminhos de outra frente: a lista acima cobre os 329 caminhos atuais. Não há caminho de outra frente fora dela. Conferir antes do commit com `git status` (o humano deve revisar `config/routes.rb` e `db/schema.rb`).

## 6. Ordem de aplicação

1. c1 (modelos e migrações, com `db/schema.rb`)
2. c2 (runtime + transferência + specs; depende de c1)
3. c3 (UI; depende de c2 pelas rotas)
4. c4 (deploy e runbooks; independente)
5. c5 (scripts G0; independente)
6. c6 (contexto; por último, para refletir o estado final)
7. c7 (evidências; por último)

Após cada commit, rodar `git diff --check` e, se possível, o spec do grupo (`spec/connecta/`) antes de seguir.

## 7. Comandos prontos (NÃO executar sem revisão humana)

Verificação antes de tudo (somente leitura):

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep
git status --porcelain -uall | wc -l   # esperado: 329
git diff --check
```

Commit c1 (exemplo; ajustar a lista se a revisão mudar algo):

```sh
git add db/migrate/20261024000000_create_connecta_human_number_tables.rb \
        db/migrate/20261024000001_add_enforcement_to_connecta_scoped_inboxes.rb \
        db/schema.rb app/models/connecta
git commit -m "feat(connecta): adiciona tabelas e modelos do número humano"
```

Commit c2 (runtime, ACL, escopo e transferência; a lista completa de caminhos vem de `/tmp/opencode/final/c2.txt`, 135 linhas, gerada pelo `git status` desta frente):

```sh
# Lista exata: cat /tmp/opencode/final/c2.txt | xargs -d '\n' git add --
# Não usar git add -A. Caminhos de c2 (resumo): app/services/connecta/**,
# app/jobs/connecta/**, app/controllers/connecta/**, app/controllers/api/v1/accounts/connecta/**,
# app/controllers/api/v1/accounts/conversations/connecta_*, app/channels/application_cable/connection.rb,
# config/routes.rb, config/initializers/connecta_runtime.rb, spec/connecta/**, spec/requests/connecta/**,
# spec/support/connecta/**
git commit -m "feat(connecta): runtime de ACL, escopo e transferência com contrato v1"
```

Commit c3 (UI, 22 caminhos):

```sh
git add -- app/javascript app/views/layouts/vueapp.html.erb app/controllers/dashboard_controller.rb
git commit -m "feat(connecta): interface de transferência e configurações no dashboard"
```

Commit c4 (deploy e runbooks, 7 caminhos):

Nota FORK-c10: `deploy/baileys-api/docker-compose.yml` e `deploy/baileys-api/README.md` mudaram nesta frente. A imagem do baileys-api passou a ser `ghcr.io/fazer-ai/baileys-api:v1.21.0@sha256:…` e o Redis `redis:7-alpine@sha256:…`; o TODO do README foi substituído pela seção de procedência (repositório, tag, digest, data e comandos). Esses dois arquivos entram neste commit.

```sh
git add -- deploy/baileys-api docs/runbooks/connecta-baileys-e2e-homologacao.md \
        docs/runbooks/connecta-baileys-saude.md docs/runbooks/connecta-numero-contingencia.md
git commit -m "chore(connecta): manifesto baileys-api e runbooks de saúde e contingência"
```

Commit c5 (scripts G0, 2 caminhos):

```sh
git add -- scripts/connecta
git commit -m "test(connecta): scripts de ambiente de teste G0"
```

Commit c6 (contexto sem evidências, 21 caminhos):

Nota FORK-c10: este próprio plano (`.context/plans/2026-10-25-plano-commit-connecta.md`) entra no c6, pela inclusão de `.context/plans`.

```sh
git add -- .context/AI-GOVERNANCE.md .context/PROJECT_STATE.md .context/README.md \
        .context/REPOMAP.md .context/architecture.md .context/archive .context/changelog \
        .context/decisions .context/gotchas.md .context/plans
git commit -m "docs(connecta): contexto do projeto, decisões e changelog"
```

Commit c7 (evidências, 128 caminhos):

```sh
git add -- .context/evidence
git commit -m "docs(connecta): evidências das frentes G0 e F3–F7"
```

Após c1–c7, conferir com `git status --porcelain -uall` (deve sair vazio) e `git log --oneline -n 7`. Nenhum desses comandos foi executado nesta frente.
