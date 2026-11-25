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
