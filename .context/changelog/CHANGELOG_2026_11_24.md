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
