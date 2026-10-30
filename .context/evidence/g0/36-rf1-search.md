# 36 — RF1 Search (TASK_ID g0-rf1-search) — FILTRO INDIVIDUAL, ESCRITO E NÃO EXECUTADO

Somente escopo autorizado: 2 alvos estáveis (`copilot_tool_hook.rb`, `captain_scope_spec.rb`)
para correção mínima de sintaxe/estilo + registro. Sem novo RF, sem teste funcional, sem runtime.
Specs ESCRITOS e NÃO EXECUTADOS. Sem teste verde inventado.

## 1. Código RF1 (função do Coder anterior, já escrita; NÃO refeita aqui)

- Arquivo: `app/services/connecta/scope/copilot_tool_hook.rb` (untracked `??`).
- Função: `connecta_scope_copilot_search_contacts` filtra CADA resultado ANTES de formatar —
  escopo visível do próprio ator (`ContactVisibility.visible_scope`), filtros nativos 1:1
  (email/phone_number/name) aplicados SOBRE esse escopo; nenhum alheio chega ao
  `LlmFormatter`/resposta. Sem filtro = só visíveis do ator. Sem usuário = fail-closed.
- Correção mínima DESTA tarefa (só sintaxe/estilo, sem refatorar fluxo/novo comportamento):
  par de disable local `Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity`
  com justificativa curta no próprio método (filtro coeso; fatiar piora clareza). Nenhum
  executável alterado, nenhum disable global/all. Campos globais (custom_attributes/notas)
  ficam para RF2 posterior — NÃO tocados aqui.

## 2. Casos RF1 escritos e NÃO EXECUTADOS (execução pendente)

Contagem real por `it`: 36 exemplos no arquivo; bloco RF1 = 3 exemplos (linhas 305-363),
sem Gate stubado, contra o contrato real:

1. Busca ampla/sem filtros de A: só formata o permitido + unmarked (sem ID/nome/telefone/content de B).
2. Nome compartilhado "Maria": A vê só o seu + unmarked; B vê só o seu + unmarked;
   membro sem grant vê só o unmarked.
3. Filtro nativo preservado: `email` alheio nega (`No contacts found`) e autorizado mantém positivo.

Runs reservados à validação consolidada. Estado escrito = PENDENTE EXECUÇÃO.

## 3. Checagens reais desta tarefa (2 alvos, sem runtime)

Comandos (caminhos absolutos, receita `scripts/connecta/g0_test_env.sh:47-49` + `gotchas.md:43`):

```sh
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c app/services/connecta/scope/copilot_tool_hook.rb
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c spec/connecta/captain_scope_spec.rb
env -i PATH=.../ruby/3.4.4/bin:... BUNDLE_GEMFILE=... BUNDLE_PATH=... BUNDLE_FROZEN=true bundle exec rubocop --format simple <2 alvos>
git diff --no-index --check /dev/null <2 alvos>
git diff --check
git status --short
df -h /tmp
```

- Resultado factual: `ruby -c` 3.4.4 `Syntax OK` nos 2 alvos; RuboCop check-only
  `env -i` + BUNDLE do launcher nos 2 alvos → **2 arquivos, 0 ofensas**, EXIT 0, stderr vazio.
  Antes dos fixes mínimos: 6 ofensas (hook AbcSize/Cyclomatic/Perceived; spec
  MultipleExpectations + 2 MultilineMethodCallIndentation); depois: 0.
- Whitespace: `git diff --no-index --check /dev/null` vazio nos 2 (exit 1 = há diff
  contra /dev/null, semântica de `29-regressao-lint.md` §6; só saída conta).
- `git diff --check` (rastreado): limpo. `git status --short`: só os 7 grupos `??`
  pré-existentes (nenhum rastreado modificado). `df -h /tmp` 7.6G/67% (leitura, sem apagar).
- Nenhum spec/teste funcional executado; nenhum build/SQL/banco/.env/migração/teardown;
  sem servidor/produção/QR/commit; PROJECT_STATE não editado.

## 4. Gap funcional percebido (NÃO corrigido aqui; reportar em vez de marcar success)

- `connecta_scope_copilot_tool_denied?` (hook `copilot_tool_hook.rb:99-104` após edição) NÃO é
  chamada por nenhum caminho: `execute` usa só `search_contacts` + `guard_text`
  (que cobre GetConversation/GetContact via display_id/contact_id). Método morto aparente —
  RF posterior decide remover ou ligar; sem mudança de comportamento nesta tarefa.

## 5. Juiz (veredito 1 preservado, sem modificar resultado)

- `verdict-try1.md` em `/home/thanos/.local/state/codex-judge/20261024T192516-1387110/`
  (6371 bytes): `VERDICT: REJECTED` — 6 RFs (REQUIRED_FIXES 1-6), sem aprovação inventada.
  REQUIRED_FIX 1 = este RF1 (filtrar cada resultado de SearchContacts + casos ampla/Maria).
  Espelho em `.context/evidence/g0/36-juiz-r1.md` (só relatório final pequeno, sem events inteiro).

## 6. Fontes

- `.context/README.md` + `gotchas.md` — orientação/receita (43: env-i + BUNDLE; 45: /tmp leitura).
- Log RF1 parcial `/home/thanos/.local/state/opencode-coder/20261024T193824-1430622`
  (código + draft spec; sintaxe/lint/docs NÃO rodados — rodados AGORA neste doc, §3).
- Veredito 1 `/home/thanos/.local/state/codex-judge/20261024T192516-1387110/verdict-try1.md`
  (REJECTED 6 RFs; resultado NÃO modificado).
