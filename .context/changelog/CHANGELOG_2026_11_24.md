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
