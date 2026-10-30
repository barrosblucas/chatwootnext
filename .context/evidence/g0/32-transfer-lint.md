# 32 — Lint Transfer (TASK_ID g0-fix-transfer-lint)

Somente lint/sintaxe nos arquivos proprios. Nenhuma spec executada; 40/0 da evidencia 25 seguem como referencia pendente de reexecucao pos-frentes.

## Ofensas filtradas do JSON 29 (Transfer + 4 specs)

Total no JSON 29 para o escopo: 14 (8 em `local_transaction.rb`, 1 em `transfer_cutover_spec.rb`, 5 em `transfer_integration_spec.rb`).
Os outros 6 arquivos Transfer e as specs `transfer_activation`/`outbound_dispatch` ja estavam limpos (0 ofensas).

## Correcoes (minimas, sem mudar contrato)

- `app/services/connecta/transfer/local_transaction.rb`
  - `Rails/TransactionExitStatement` (`call:35`): `return WAIT` → `next WAIT` dentro do bloco de `ActiveRecord::Base.transaction`. `next` devolve o valor como resultado do bloco sem acionar o gatilho de exit do cop e sem alterar commit/rollback: o bloco nao lanca, a transacao commita normalmente com o valor WAIT como retorno de `call` — mesma semantica anterior, agora sem ambiguidade de `return` em bloco de transacao.
  - `Style/RedundantBegin` (`commit_local!:93`): `begin/rescue/end` dentro do bloco `locked do` removido; `rescue ConflictError` passou ao corpo do bloco (block-rescue). Caminho feliz e caminho de conflito identicos.
  - `Lint/UnusedMethodArgument` (`retry_open_record!:230`): parametro `origin` → `_origin` (assinatura preservada).
  - `Metrics/ClassLength` + `Metrics/AbcSize,CyclomaticComplexity,MethodLength,PerceivedComplexity` (classe + `commit_local!`): disables locais com par `disable/enable` (metodo) e inline (classe). Justificativa: maquina de estados T0.3/T0.7 coesa e commit atomico com barreira T0.7c; fatiar espalharia transicao/lock/dispatch e pioraria clareza. Sem `disable all`, sem global.
- `spec/connecta/transfer_cutover_spec.rb`
  - `RSpec/ExampleLength` (`:119`, 56/50): disable local com `enable` apos o bloco (concorrencia + ensure/join + limpeza por IDs + 21 assercoes atomicas; fatiar quebraria o `after`).
- `spec/connecta/transfer_integration_spec.rb`
  - `Lint/AmbiguousBlockAssociation` ×5 (91, 102, 134, 147–148): `.to raise_error { }` → `.to(raise_error { })`; bloco continua ligado ao `raise_error`, assercao inalterada.

Contrato preservado: locks, estados (`requesting/awaiting_dispatch/committed_local/transferred_out/pending_activation/aborted`), barreira dispatch (`prepare/recheck/settle`), idempotencia (`reuse/retry/commit` repetido), `pending_activation` ate `activate!`, cleanup por IDs sem tocar residuos antigos. Nenhum estado/lock/dispatch alterado.

## Validacao

- Sintaxe Ruby 3.4.4 (`env -i` + BUNDLE_* do launcher): `ruby -c` OK nos 3 alterados.
- RuboCop check-only `env -i` Ruby 3.4.4 + BUNDLE_* do launcher, sem autocorrect:
  `bundle exec rubocop app/services/connecta/transfer spec/connecta/transfer_cutover_spec.rb spec/connecta/transfer_activation_spec.rb spec/connecta/outbound_dispatch_spec.rb spec/connecta/transfer_integration_spec.rb`
  → **11 files inspected, no offenses detected**, EXIT 0. Log: `32-logs/transfer-lint.log` (stderr vazio).
- `git diff --check`: limpo (rastreado). Untracked (`??` pre-existentes): `git diff --no-index --check /dev/null <arquivo>` sem saida nos 11 arquivos. `git status --short`: so os 7 grupos `??` pre-existentes. `df -h /tmp`: 67% (leitura, sem apagar).
- Specs NAO executadas (outras frentes em mutacao): revalidacao funcional dos 40 casos pendente para o validador pos-frentes.
