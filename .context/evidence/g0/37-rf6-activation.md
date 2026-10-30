# 37 — RF6 Activation (TASK_ID g0-rf6-activation) — FECHAMENTO ESTÁTICO, ESCRITO E NÃO EXECUTADO

Somente escopo autorizado: 2 alvos estáveis (`local_transaction.rb`, `transfer_activation_spec.rb`)
para fechamento de sintaxe/estilo + registro. RF6 já escrito pelo Coder anterior; aqui NÃO
reimplementado do zero, só fechamento pendente. Sem outra transferência, sem teste funcional, sem runtime.
Specs ESCRITOS e NÃO EXECUTADOS. Sem teste verde inventado.

## 1. Código RF6 (função do Coder anterior, já escrita; NÃO refeita aqui)

- Arquivo: `app/services/connecta/transfer/local_transaction.rb` (untracked `??`).
- Função: `activate!` idempotente com a mesma versão confirmada, sem reabrir origem.
  `activation_record!` resolve o transfer pela origem verificada (`source_conversation_id`
  do scope, estados `committed_local`/`committed`, exatamente 1; trava `@record` da mesma
  instância), nunca pelo "último destino". `activate!` recusa versão diferente da alvo
  ANTES de qualquer escrita (`VersionMismatch`, origem `transferred_out` preservada).
  Primeira ativação exige destino `pending_activation` com `case_version` 0 e mesmo
  (inbox, contato) (`require_pending_destination!`); repetição com a mesma versão exige
  destino `active` com a versão alvo gravada nos dois lados (`require_committed_destination!`).
  Repetir com versão diferente depois de ativo continua recusado (`VersionMismatch`).
  Origem nunca reabre (só `abort!` pré-commit volta a `active`; `commit_local!` repetido
  devolve o destino criado). `mark_stuck!` exige `committed_local`.
- Correção mínima DESTA tarefa (só sintaxe/estilo, sem refatorar fluxo/novo comportamento):
  `activation_record!`: quebra de 2 linhas → chamada `where` em 1 linha (150 chars,
  dentro do `Layout/LineLength Max: 150`) + `unless` aninhado fundido na condição externa
  (`Style/SoleNestedConditional`: `if !nil && !nil && id !=` com `raise` em modifier `if`,
  `Style/IfUnlessModifier`). Nenhum executável alterado, nenhum disable global/all,
  nenhuma trava/lock/estado/barreira/cleanup tocada.

## 2. Casos RF6 escritos e NÃO EXECUTADOS (execução pendente)

Blocos no `spec/connecta/transfer_activation_spec.rb` (untracked `??`), sem mock do
Gate/lock/registro, contra o contrato real (origem `transferred_out`, destino
`pending_activation → active`, mensagens/auditoria/gate reais):

1. `activate! com versão diferente da confirmada é recusado e não muda nada`
   (pré-ativo): `activate!(case_version: 1)` com alvo 2 levanta `VersionMismatch`
   (classe comparada por nome); destino segue `pending_activation`/`case_version` 0;
   registro segue `committed_local`.
2. `activate! repetido com a mesma versão é idempotente: mesmo destino, sem efeitos novos`:
   ativa com 2, reativa na mesma instância E em instância nova
   (`LocalTransaction.new(scope: origin_scope, ...)` — resolve pela origem, não pelo
   "último destino"); `expect { ... }.not_to change { [TransferRecord.count,
   Conversation.count, Message.count] }`; registro `committed` com `target_case_version` 2
   e mesmo `destination_conversation_id` nas duas instâncias; destino `active`/`case_version` 2.
3. `activate! com versão diferente depois de ativo é recusado sem mudar nada`:
   após ativar com 2, `activate!(case_version: 3)` levanta `VersionMismatch`;
   registro segue `committed`/alvo 2; destino segue `active`/2; origem segue `transferred_out`.

Mais cobertura no mesmo arquivo (fora do RF6 estrito, contexto da barreira):
pending entra no destino pela `IncomingHook` real, 404 do agente do destino em
`pending_activation`, leitura auditada do admin nominal, `mark_stuck!` só-admin,
`abort!` pós-commit recusado, escrita de A negada, `toggle_status` negado, `begin!/abort!`
pré-commit. Nenhum caso eliminado ou afrouxado aqui.

Runs reservados à validação consolidada. Estado escrito = PENDENTE EXECUÇÃO.

## 3. Checagens reais desta tarefa (2 alvos, sem runtime)

Comandos (caminhos absolutos, receita `scripts/connecta/g0_test_env.sh:47-49` + `gotchas.md:43`):

```sh
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c app/services/connecta/transfer/local_transaction.rb
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c spec/connecta/transfer_activation_spec.rb
env -i PATH=.../ruby/3.4.4/bin:... BUNDLE_GEMFILE=... BUNDLE_PATH=... BUNDLE_FROZEN=true bundle exec rubocop --format simple <2 alvos>
git diff --no-index --check /dev/null <alvo> (1 por alvo; 2 caminhos juntos não são suportados)
git diff --check
git status --short
df -h /tmp
```

- Resultado factual: `ruby -c` 3.4.4 `Syntax OK` nos 2 alvos, EXIT 0; RuboCop check-only
  `env -i` + BUNDLE do launcher nos 2 alvos → **2 arquivos, 0 ofensas**, EXIT 0.
  Antes dos fixes mínimos: 3 ofensas (hook ArgumentAlignment/HashAlignment na quebra do
  `where` + SoleNestedConditional no `unless` aninhado); depois: 0. Spec sem ofensa
  antes e depois (nenhuma edição nele aqui).
- Whitespace: `git diff --no-index --check /dev/null` vazio em CADA alvo (exit 1 = há
  diff contra /dev/null, semântica de `29-regressao-lint.md` §6; só a saída conta;
  comando com os 2 caminhos juntos falha com exit 129 por sintaxe do git, não por
  whitespace — ver §5).
- `git diff --check` (rastreado): limpo. `git status --short`: só os 7 grupos `??`
  pré-existentes (nenhum rastreado modificado). `df -h /tmp` 7.6G/5.1G/67% (leitura,
  sem apagar). Binário `ruby` 3.4.4 absoluto confirmado (`-v` = `ruby 3.4.4 ... +PRISM`).
- Nenhum spec/teste funcional executado; nenhum build/SQL/banco/.env/migração/teardown;
  sem servidor/produção/QR/commit; PROJECT_STATE não editado (fora de escopo).

## 4. Incompletudes descobertas (concretas, listadas)

1. Defesa do judge RF6 (juiz `20261024T192516`, REQUIRED_FIX 6): "`activate!` repetido
   com a mesma versão lançava `RecordNotFound` porque procurava só `committed_local`"
   (`local_transaction.rb:144` da época). Fechado pelo código do Coder anterior
   (`activation_record!` aceita `committed_local`/`committed` + `require_committed_destination!`
   + regressões mesma-versão/nova-instância/versão-diferente no spec). AQUI: só
   sintaxe/estilo/doc; execução pendente.
2. Interrupção do turno anterior (coder `20261024T193824`, `report-final.txt` BLOCKED):
   código + spec RF6 escritos, mas `ruby -c`/`rubocop`/whitespace/`git diff --check`/
   `git status`/doc 37/changelog NÃO rodados — todos executados aqui, exceto runtime.
3. 3 ofensas RuboCop no `local_transaction.rb` herdadas do código RF6 (detalhe §3).
   Corrigidas aqui com 2 edições mínimas de estilo (§1), sem mudar comportamento.
4. Spec `transfer_activation_spec.rb` sem ofensa e sem edição necessária aqui.
5. Runtime PENDENTE: os 3 casos RF6 + restante da barreira estão escritos e NÃO
   EXECUTADOS; nenhuma afirmação de verde funcional neste doc.

## 5. Armadilha de comando (para não custar outra rodada)

- `git diff --no-index --check /dev/null <T1> <T2>` NÃO aceita 2 caminhos quando o
  segundo é pathspec: `warning: Limiting comparison with pathspecs is only supported
  if both paths are directories` + exit 129. Rodar 1× por alvo. Evidência: saída do
  comando nesta tarefa (antes da correção do procedimento).
- `bundle`/`rubocop` via shim do mise sem versão falha (`mise ERROR No version is set
  for shim`); usar `env -i` com `PATH=<toolchain>/ruby/3.4.4/bin` + `BUNDLE_GEMFILE`/
  `BUNDLE_PATH`/`BUNDLE_FROZEN` do launcher (fonte: `gotchas.md:43`,
  `scripts/connecta/g0_test_env.sh:47-49`).
- `/tmp` é tmpfs 7.6G compartilhado (67% aqui); só leitura com `df -h`, sem apagar
  (fonte: `gotchas.md:45`).
