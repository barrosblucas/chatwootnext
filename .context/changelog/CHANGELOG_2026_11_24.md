# Changelog — 2026-11-24

## Correção 02 — abas Conecta (Minhas, Aguardando, Todos, Bot) em inbox Baileys compartilhada (somente registro; sem release)

- Base estável verificada: `e9baeaaf0f88175cb06f4968502cde17035f5d12` em `fix/connecta-abas-chatwoot` (isolado em `/tmp/opencode/chatwootnext-correcao-02`); nada publicado neste passo.

## Intenção da feature — Correção 02

- Intenção: abas Minhas, Aguardando, Todos e Bot refletem o modelo de caixa única Baileys compartilhada com separação por setor via menu/roteamento (Conecta Saúde): o cidadão escolhe a opção no menu e é direcionado ao setor; cada atendente vê somente os chamados do seu setor autorizado, com agregação e seletor de setor sobre a inbox compartilhada.
- Regras de negócio afetadas: Minhas = atribuídas ao atendente; Aguardando = triagem com setor habilitado e protocolo; Todos/Bot = somente admin da conta; agregação por setor autorizado + seletor sobre a inbox Baileys compartilhada; contagem/listagem via API com escopo comum e badge desconhecido em erro; empty-state do Bot corrigido.
- Não deve mudar: nada além do registro neste passo — sem código, workflow, main, dados, produção, build/teste além de checagens estáticas leves, commit/push/PR/deploy ou outras correções; `script/criar_admin.rb` não lido/não tocado; comportamento implantado não afirmado a partir de doc canônico.
- Já feito: implementação existente no fork (`app/services/connecta/scope/dashboard_tabs.rb`, hook no finder, `Api::V1::Accounts::Connecta::OrgUnitsController`, config/routes, JS ChatList/api/stores/helper e specs sintéticas); 36 testes direcionados aprovados somente no slice inicial de UI (4 de componente + 32 vizinhos); nos slices posteriores somente `node --check`/parse JS e `git diff --check` aprovados.
- Pendente: todas as novas specs de integração, CI próprio Rails/Vitest, smoke em navegador; sem status implantado.
- Etapa atual: somente changelog datado — anexar/criar `CHANGELOG_2026_11_24.md` no layout existente, preservando demais arquivos/entradas; próximo portão definido = CI próprio + smoke antes de qualquer relato de implantado.

## Correção 02 — remediação CI (Rails 2 falhas + RuboCop 20 + ESLint 37; sem publish)

- Base: `177c6aeb6249bc137f6f1c88052208238d7ea5a3` em `fix/connecta-abas-chatwoot` (isolado em `/tmp/opencode/chatwootnext-correcao-02`); original `/home/thanos/chatwootnext` não tocado. Nada publicado neste passo (sem commit/push/dispatch/deploy; sem lockfile/workflow/DB/serviço).
- Intenção: reparar na fonte os dois exemplos `spec/connecta/scope_dashboard_tabs_spec.rb:154` e `:272` (runs `45434689831`), os 20 offenses RuboCop e os 37 erros ESLint/Prettier (run `45434689895`), preservando comportamento e sem enfraquecer testes.
- Causa Rails (154 — outsider sem grant via `human_only` + passthrough de inbox não-marcada retornava `generic`/all_count 1): `DashboardTabs.apply` agora falha fechado (`none`) para não-admin sem nenhum setor legível (`sectors_granted?`: admin nativo ou projeção utilizável + grant de leitura; lista e meta na mesma relação, sem vazar totais).
- Causa Rails (272 — sem inbox marcada o opt-in devolvia a relação sem filtrar a aba): removido o retorno antecipado `return relation if marked_ids.empty?`; o predicado da aba (`assigned_to` em Minhas, demais inalterados) sempre aplica sobre a base autorizada.
- RuboCop: `IfInsideElse` → `elsif` e alinhamento de cadeia no `filter_by_query` (`conversation_finder_hook.rb`); `apply_tab` extraído em `bot_tab`/`todos_tab`/`raise_unless_bot_available?` (complexidade 8→≤5) + `sectors_granted?` com a mesma regra de `sector_allowed?` (`dashboard_tabs.rb`); specs com `let/let!` agrupados, `match_array`, alinhamento de chaves e `let`→`def` em auxiliares de caminho (`*_spec.rb`, sem mudar comportamento).
- ESLint: reordenadas declarações (`isConnectaDashboard`/`connectaBadgeCount`/`resetAndFetchData` antes do uso em `ChatList.vue`), `no-multi-assign` desmembrado, ternários aninhados viraram `if/else` com mesma semântica (`actions.js`), `default-param-last` resolvido movendo `assigneeKey` para primeiro parâmetro com todos os chamadores atualizados (`ChatList.vue` + spec), restante Prettier aplicado a partir das evidências file:line do CI.
- Não mexido: advisories do security-scan (bundle-audit puma/rack-protection, pré-existentes) — portão separado pendente; Vitest não rodou (lint travava antes); `ReplyToChip.vue` sem erro (só warnings pré-existentes do projeto).
- Checagens locais: `git diff --check` limpo; `node --check` OK nos 10 `.js` alterados (`.vue` sem checker local; sem ruby/eslint instalados — sem install, sem suíte local, sem DB).
- Pendente (próximo portão, sem dispatch neste passo): `gh workflow run "Run Chatwoot CE spec" --ref fix/connecta-abas-chatwoot`, `gh workflow run "Frontend Lint & Test" --ref fix/connecta-abas-chatwoot`, depois `gh run view` dos novos runs + security-scan; só então push.

## Correção 02 — slice isolado: 500 do Bot admin + 2 lint exatos (sem publish)

- Base: `8e75802df0c52c18458733d4f51bf2f7932873f7` em `fix/connecta-abas-chatwoot` (isolado em `/tmp/opencode/chatwootnext-correcao-02`); `git status` limpo antes e 2 arquivos modificados depois. Nada publicado neste passo (sem commit/push/dispatch/deploy; sem Gemfile/lockfile/workflow; sem `.env`/dados; `script/criar_admin.rb` não lido).
- Intenção: reparar na fonte o 500 do exemplo admin Bot (`spec/connecta/scope_dashboard_tabs_spec.rb:245`, run `45479644528`, job backend-tests `138749143706`: 59 exemplos/1 falha) + o erro Prettier `getters.js:215:5` + o offense RuboCop `dashboard_tabs.rb:94`, preservando comportamento (abas marcadas/não-marcadas, escopo por setor autorizado, fronteiras admin).
- Causa Rails (evidência código+log): `bot_tab` chamava `raise_unless_bot_available!` (bang, `dashboard_tabs.rb:95`) mas a definição era `raise_unless_bot_available?` (interrogação, `:100`) → `NoMethodError ... for class Connecta::Scope::DashboardTabs` (`test.log` do artefato `rails-log-folder-0`, `Completed 500 ... in 60ms`); HTML de erro quebrava `JSON.parse` no spec (`:59`). Correção: renomear a definição para bang (2 referências totais, chamador inalterado) — sem rescue novo, sem enfraquecer contagens/acesso; indisponibilidade real continua 503 via `Unavailable` (rescue existente no controller).
- Lint: `getters.js:215` menos 2 espaços (Prettier pedia Delete de 2 espaços, 1 linha); `dashboard_tabs.rb:94` linha em branco após guard clause (`Layout/EmptyLineAfterGuardClause`). Sem supressões, sem reformat alheio.
- Não mexido: advisories do security-scan (puma 7.2.2 GHSA-4v6q-hvv7-49h9 fix ~>7.2.3; rack-protection 4.1.1 GHSA-pf75-2v58-7mxg/GHSA-r29j-38x9-qr26/GHSA-vvhm-j6m8-64cw fix >=4.2.2) — ação separada pendente, sem override/manifest neste passo.
- Checagens locais: `git diff --check` limpo; `node --check` OK em `getters.js`; `gh run view 45479644528 --job 138749143706 --log-failed` lido (causa acima); Ruby ausente nesta VM então sem suíte local — testes Rails/Vitest marcados pendentes Actions.
- Pendente (próximo portão, sem dispatch neste passo): novo run oficial `Run Chatwoot CE spec` no branch + `gh run view` do backend-tests/lints/security-scan; só então push/publicação.

## Correção 02 — lockfile audit via resolver isolado (puma/rack-protection/rack; sem main/deploy)

- Base: `8e75802df0c52c18458733d4f51bf2f7932873f7` em `fix/connecta-abas-chatwoot` (isolado em `/tmp/opencode/chatwootnext-correcao-02`); 3 correções 500/lint anteriores preservadas; só `Gemfile.lock` adotado deste passo.
- Intenção: resolver via Bundler oficial os advisories puma GHSA-4v6q-hvv7-49h9 (fix 7.2.3) e rack-protection GHSA-pf75-2v58-7mxg/GHSA-r29j-38x9-qr26/GHSA-vvhm-j6m8-64cw (fix 4.2.2), sem toolchain local.
- Resolver: workflow temporário `Connecta lock resolver (temporary)` no ref isolado `ci/chatwoot-c02-lock-resolver` (nunca mergeado); run 1 `45499496162` rejeitou `rack 3.2.8→3.2.9` transitivo; guard corrigido para aceitar o patch exato (rack 3.2.9 é release de segurança 2026-11-20, 5 GHSAs, e satisfaz `rack-protection 4.2.2: rack >= 3.0, < 4`); run 2 `45499942763` verde (`GUARDS: PASS`, HEAD `8e75802`, https://github.com/barrosblucas/chatwootnext/actions/runs/45499942763).
- Artefato `connecta-lock-resolver-output` verificado: só 3 linhas spec (`puma 7.2.2→7.2.3`, `rack 3.2.8→3.2.9`, `rack-protection 4.2.1→4.2.2`), `Gemfile`/`DEPENDENCIES`/`RUBY VERSION`/`BUNDLED WITH`/`PLATFORMS` intactos, lockfile parseado.
- Checagens locais: `git diff --check` limpo; `git diff -U0 -- Gemfile.lock` só as 3 trocas; sem suíte local (sem Ruby nesta VM).
- Pendente (próximo portão): commit/push `fix/connecta-abas-chatwoot` + runs oficiais `Run Chatwoot CE spec` (full=true) e `Frontend Lint & Test`; sem relato de audit fechado só pelo resolver.
