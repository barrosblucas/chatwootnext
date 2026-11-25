# Changelog — 2026-11-25

## Correção 02 — Bot tab: expectativa `empty`→`ready` no caso populado + caso vazio independente (sem merge/deploy)

- Base: `3b91a4205e35474cf5b3b009a1a03714ad4a1bf2` em `fix/connecta-abas-chatwoot` (isolado em `/tmp/opencode/chatwootnext-correcao-02`); main remota viva `e9baeaaf0f88175cb06f4968502cde17035f5d12` (ancestral do HEAD, sem drift); sem produção alterada. Nada publicado neste passo até o push abaixo.

## Intenção da feature — Correção 02 (Bot tab)

- Intenção: corrigir a única falha observada do run `Frontend Lint & Test` `45507012119` (5154 passed, 23 skipped, 1 failed) sem enfraquecer asserções e sem tocar fonte/Ruby.
- Regras de negócio afetadas: nenhuma — contrato da fonte mantido (`actions.js:fetchBotConversations` commita `SET_BOT_LIST_STATUS` `ready` com payload não-vazio, `empty` só com payload vazio; `SET_BOT_CONVERSATIONS` com `ids`+`page`).
- Não deve mudar: fonte (`actions.js`), Ruby, workflows, lockfile, main, produção, build/suíte local nesta VM; `script/criar_admin.rb` não lido/não tocado.
- Já feito: causa raiz evidenciada (abaixo); teste corrigido + novo caso vazio independente; `git diff --check` limpo; `node --check` OK no spec; sem `node_modules` (sem Vitest local — portão oficial hospedado).
- Pendente: commit/push sem force + runs oficiais (`Frontend Lint & Test` no novo SHA; CE direcionada nos 3 specs se exigida pelo portão) com IDs/estados; sem claim de verde local.

## Causa raiz (evidência código + run oficial)

- O exemplo `connectaTabs.spec.js:149` (`fetchBotConversations > feeds the Connecta bot slot from the same exact answer`) alimenta resposta populada (`all_count: 2`, `payload: [{ id: 5 }]`) mas exigia `SET_BOT_LIST_STATUS` = `empty`. A fonte (`actions.js:212-215`) commita `data.payload.length ? 'ready' : 'empty'`, logo o correto para payload `[5]` é `ready` + `SET_BOT_CONVERSATIONS { ids: [5], page: 1 }` — exatamente o que o run `45507012119` observou (`loading`, membership `[5]` page 1, `ready`). Expectativa errada, não contrato errado; `beforeEach` com `vi.clearAllMocks()` sem vazamento entre exemplos.
- Reparo só no spec: exemplo populado agora exige `SET_BOT_CONVERSATIONS { ids: [5], page: 1 }` + `ready`; novo exemplo independente (`all_count: 0`, `payload: []`) exige `ids: []` + `empty`. Asserções fortes dos dois estados preservadas; 503/`unavailable` inalterado.

## Publicação e validação oficial (preencher após dispatch)

- Commit/push: (SHA novo + `git status` após).
- `Frontend Lint & Test`: (run ID + estado).
- CE direcionada `spec/connecta/scope_dashboard_tabs_spec.rb spec/connecta/org_units_catalog_spec.rb spec/connecta/transfer_schema_smoke_spec.rb`: (run ID + estado, se exigida).
- Sem merge/PR/deploys neste passo; em verde, recomendar PR normal como próximo passo.

## Correção C02 — admissão manual: fixture UUID produto isolada no spec (sem merge/deploy)

- Base: `22ca5c2e242efb72a88f55c3e23686ea6cd97c35` (main viva verificada via `ls-remote` == `origin/main` antes do checkout) em `fix/connecta-c02-admission-spec` (isolado em `/tmp/opencode/chatwootnext-c02-admission`); main original `/home/thanos/chatwootnext` intacta (8 linhas pendentes em `.context/changelog/CHANGELOG_2026_11_25.md` + `?? script/criar_admin.rb` preservados, script nunca lido); produção `e9baeaaf0` (ancestral do HEAD, sem drift). Nada publicado neste passo até o push abaixo.

## Intenção da feature — Correção C02 (admissão manual UUID)

- Intenção: reparar os 6 exemplos com 422 do run CE `45518055531` shard 1 (`spec/connecta/manual_admission_flow_spec.rb:59,76,89,112,131,171`) sem tocar validadores, rotas, auth, schema ou asserções 201/200/403.
- Regras de negócio afetadas: nenhuma — contrato mantido (`ManualAdmissionTransaction:63-66,77-79` continua exigindo `org_unit_id` UUID; `ensure_org_unit!`/`uuid_format?` inalterados).
- Não deve mudar: fonte (`app/`), validadores implantados, rotas, auth, schema, traduções, workflows, `.env`/segredos, checkout original, G0 bigint (dashboard/catálogo seguem com cobertura dupla bigint+UUID), build/suíte local nesta VM; `script/criar_admin.rb` não lido/não tocado.
- Já feito: causa raiz evidenciada (abaixo); spec remapeado + `git diff --check` limpo; sem Ruby local (portão oficial hospedado).
- Pendente: commit/push sem force + run oficial CE direcionada no novo SHA com IDs/estados; sem claim de verde local.

## Causa raiz (evidência código + run oficial)

- O fixture compartilhado (`support/g0_scope_fixture.rb`) cria `org_a` em `Connecta::Scope::OrgUnit` (tabela `connecta_g0_org_units`, id bigint); o spec enviava `org_a.id.to_s` (ex.: `"123"`) como `org_unit_id`, e `ManualAdmissionTransaction#ensure_org_unit!` rejeita não-UUID com 422 — 6 exemplos de admissão viraram 422 em vez de 201/200. Expectativa/fixture erradas, não contrato errado.
- Reparo só no spec: `around` isola os 6 modelos de escopo nas tabelas produto `connecta_*` (ids UUID, mesmo mapa do `G0Adapter.install!`, sem hooks globais; restaura tabelas + `reset_column_information` no `ensure`); módulo de teste `ConnectaAdmissionProductGrantedPaths` acompanha a tabela viva em `granted_paths` (SQL idêntico no G0 padrão, sem vazar comportamento); `scope_diag` (tabela ativa + tipo do id, sem PII) nas asserções de status; asserções 201/200/403, rollback/replay/autorização intactas.

## Publicação e validação oficial (preencher após dispatch)

- Commit/push: (SHA novo + `git status` após).
- CE direcionada `spec/connecta/manual_admission_flow_spec.rb spec/connecta/scope_dashboard_tabs_spec.rb spec/connecta/org_units_catalog_spec.rb`: (run ID + estado).
- Sem merge/PR/deploys neste passo; sem rerun frontend isolado (full main cobre); próximo portão oficial: full CE antes de EE.
