# 29 — Regressão da base G0 + 3× Captain + RuboCop (TASK_ID g0-regression-lint)

Somente diagnóstico + registro. Nenhum código/spec/runner/config/schema alterado nesta tarefa.
Sem autocorrect, sem mutação, sem SQL manual, sem teardown, sem segredos impressos.

## 0. Inventário real (19 specs, nada omitido)

Encontrados por `ls spec/connecta/*_spec.rb spec/requests/connecta/*_spec.rb` (2026-10-24):

| # | Spec | `it` estático | Status nesta tarefa |
|---|---|---|---|
| 1 | spec/connecta/agent_bot_delivery_spec.rb | 17 | G2, verde (parte de 117/123) |
| 2 | spec/connecta/attachment_access_spec.rb | 12 | G2, verde (parte de 117/123) |
| 3 | spec/connecta/attachment_download_scope_spec.rb | 27 | verde já obtido, log `28-logs/anexos-final-4.log` (27/0) — NÃO repetido |
| 4 | spec/connecta/captain_scope_spec.rb | 33 | 3 runs nesta tarefa, 33/0 cada (logs `29-logs/captain-run-{1,2,3}.log`) |
| 5 | spec/connecta/internal_chat_scope_spec.rb | 6 | G2, verde (parte de 117/123) |
| 6 | spec/connecta/outbound_dispatch_spec.rb | 10 | verde já obtido, evidência 25 (parte de 40/0) — NÃO repetido |
| 7 | spec/connecta/scope_b1_leftovers_spec.rb | 41 | verde já obtido, `26-logs/escopo-lote-b-2.log` (parte de 73/0) — NÃO repetido |
| 8 | spec/connecta/scope_b2_complements_spec.rb | 12 | verde já obtido, `26-logs/escopo-lote-b-2.log` (parte de 73/0) — NÃO repetido |
| 9 | spec/connecta/scope_http_filter_spec.rb | 34 | G1, verde (parte de 94/94) |
| 10 | spec/connecta/scope_notifications_spec.rb | 17 | G2, verde (parte de 117/123) |
| 11 | spec/connecta/scope_policy_query_spec.rb | 30 | G1, verde (parte de 94/94) |
| 12 | spec/connecta/scope_related_http_spec.rb | 64 | G2, **6 falhas** (5 neste arquivo + 1 no inventory) |
| 13 | spec/connecta/scope_socket_spec.rb | 30 | G1, verde (parte de 94/94) |
| 14 | spec/connecta/scope_team_contact_spec.rb | 20 | verde já obtido, `26-logs/escopo-lote-b-2.log` (parte de 73/0) — NÃO repetido |
| 15 | spec/connecta/transfer_activation_spec.rb | 10 | verde já obtido, evidência 25 (parte de 40/0) — NÃO repetido |
| 16 | spec/connecta/transfer_cutover_spec.rb | 4 | verde já obtido, evidência 25 (parte de 40/0) — NÃO repetido |
| 17 | spec/connecta/transfer_integration_spec.rb | 11 | verde já obtido, evidência 25 (parte de 40/0) — NÃO repetido |
| 18 | spec/connecta/transfer_schema_smoke_spec.rb | 4 | G2, verde (parte de 117/123) |
| 19 | spec/requests/connecta/route_inventory_spec.rb | 3 | G2, **1 falha** (`:204`, rota nova não classificada) |

Total: 19 arquivos. Nenhum inventado, nenhum `0ex como aprovação`.

## 1. Pré-checagens (leitura, sem matar)

- `df -h /tmp`: tmpfs 7,6 GB, 5,1 GB usados (67%), 2,6 GB livres — antes dos lotes.
- Lock: `flock -n .../spec.lock true` → livre antes de G1.
- Runner G0 residual: nenhum `g0_test_env.sh` / `bundle exec rspec` em execução além do próprio harness/opencode desta tarefa. Nada foi morto.

## 2. Lotes novos (fila obrigatória, launcher 300 s)

### G1 — policy_query + http_filter + socket (94 ex)

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_policy_query_spec.rb spec/connecta/scope_http_filter_spec.rb spec/connecta/scope_socket_spec.rb
```

- Pré-condições do runner: 11/11 `ok`.
- RSpec **94 examples, 0 failures** (`Finished in 1 minute 23.51 seconds`, files 3.85 s). Exit **0**. Duração real (parede, incluindo pré-condições): **89 s**.
- INICIO_UTC 2026-10-24T18:05:37Z, FIM_UTC 2026-10-24T18:07:06Z.
- Log: `29-logs/g1-lote-1.log`.

### G2 — related_http + notifications + internal_chat + agent_bot_delivery + attachment_access + route_inventory + smoke_schema (123 ex)

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_related_http_spec.rb spec/connecta/scope_notifications_spec.rb spec/connecta/internal_chat_scope_spec.rb spec/connecta/agent_bot_delivery_spec.rb spec/connecta/attachment_access_spec.rb spec/requests/connecta/route_inventory_spec.rb spec/connecta/transfer_schema_smoke_spec.rb
```

- Pré-condições do runner: 11/11 `ok`.
- RSpec **123 examples, 6 failures** (`Finished in 1 minute 46.88 seconds`, files 4 s). Exit **1**. Duração real: **113 s**.
- INICIO_UTC 2026-10-24T18:07:09Z, FIM_UTC 2026-10-24T18:09:02Z.
- Log: `29-logs/g2-lote-1.log`.
- G2 foi executado mesmo sendo o segundo lote (mapeamento completo, sem repetição).

## 3. Falhas G2 arquivo:linha (todas, sem correção nesta tarefa)

1. `spec/connecta/scope_related_http_spec.rb:368` (asserção `:371`) — esperava 403, resposta foi 500 (agente com membership não inicia pareamento; `show_exceptions` deprecation no setup `:390` indica erro real mascarado).
2. `spec/connecta/scope_related_http_spec.rb:375` (asserção `:378`) — esperava 403, resposta foi 422 `:unprocessable_content` (gestor não importa sessão).
3. `spec/connecta/scope_related_http_spec.rb:382` (asserção `:385`) — esperava 404, resposta foi 400 (agente não consulta saúde da inbox física).
4. `spec/connecta/scope_related_http_spec.rb:389` (asserção `:392`) — esperava 403, resposta foi 500 (agente não verifica número).
5. `spec/connecta/scope_related_http_spec.rb:396` (asserção `:398`) — esperava 403, resposta foi 401 (agente não altera/exclui inbox física; sem job).
6. `spec/requests/connecta/route_inventory_spec.rb:204` (asserção `:209`) — rota nova não classificada: `GET /api/v1/accounts/:account_id/connecta_attachments/:attachment_id/download (connecta/scope/attachment_downloads#show)`.

Os outros 117 exemplos do lote passaram sem falha registrada no log (64−5 related + 17 notifications + 6 internal_chat + 17 agent_bot + 12 attachment_access + 3−1 inventory + 4 smoke = 117).

## 4. Captain 3× consecutivas (sozinha, fila, sem retry oculto)

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/captain_scope_spec.rb
```

Comando acima rodado **exatamente 3 vezes em série**, um log por run:

| Run | Log | Examples | Falhas | Exit | Duração real | Início UTC | Fim UTC |
|---|---|---|---|---|---|---|---|
| 1 | `29-logs/captain-run-1.log` | 33 | 0 | 0 | 28 s (21.73 s RSpec) | 2026-10-24T18:09:09Z | 2026-10-24T18:09:37Z |
| 2 | `29-logs/captain-run-2.log` | 33 | 0 | 0 | 28 s (22.60 s RSpec) | 2026-10-24T18:09:37Z | 2026-10-24T18:10:05Z |
| 3 | `29-logs/captain-run-3.log` | 33 | 0 | 0 | 27 s (21.64 s RSpec) | 2026-10-24T18:10:05Z | 2026-10-24T18:10:32Z |

Pré-condições 11/11 `ok` nos 3 runs. Sem loop, sem repetição além das 3 autorizadas.

## 5. RuboCop final (check-only, `env -i`, Ruby 3.4.4, BUNDLE_* do launcher)

```sh
env -i PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:/usr/bin:/bin HOME="$HOME" LANG=C.UTF-8 BUNDLE_GEMFILE=/home/thanos/chatwootnext-connecta-g0-prep/Gemfile BUNDLE_PATH=/home/thanos/chatwootnext-connecta-g0-prep/.bundle/gems BUNDLE_FROZEN=true bundle exec rubocop --format json --out .context/evidence/g0/29-logs/rubocop-final-1.json app/services/connecta/scope app/services/connecta/transfer spec/connecta spec/requests/connecta spec/support/connecta
```

- RuboCop 1.75.6, Ruby 3.4.4. **73 arquivos, 90 ofensas**, exit **1**. Duração real 9 s. INICIO_UTC 2026-10-24T18:10:45Z, FIM_UTC 2026-10-24T18:10:54Z.
- JSON: `29-logs/rubocop-final-1.json`. stderr vazio. Sem autocorrect, sem instalação.
- Nenhum erro de inspeção (todos os 73 arquivos inspecionados; `offense_count` = soma por arquivo = 90).

### Ofensas por arquivo (todas)

- `app/services/connecta/scope/active_storage_guard.rb` (1): `42:48 Rails/WhereExists [convention]`.
- `app/services/connecta/scope/attachment_downloads_controller.rb` (3): `25:3 Metrics/AbcSize`, `Metrics/CyclomaticComplexity`, `Metrics/PerceivedComplexity`.
- `app/services/connecta/scope/attachment_token.rb` (1): `7:13 Style/MutableConstant`.
- `app/services/connecta/scope/attachment_url_hook.rb` (3): `35:3 Metrics/AbcSize`, `Metrics/CyclomaticComplexity`, `Metrics/PerceivedComplexity`.
- `app/services/connecta/scope/captain_http_hook.rb` (1): `9:49 Style/SoleNestedConditional`.
- `app/services/connecta/scope/conversation_http_hook.rb` (1): `31:5 Style/MultilineIfModifier`.
- `app/services/connecta/scope/copilot_hook.rb` (1): `21:1 Layout/TrailingEmptyLines`.
- `app/services/connecta/scope/copilot_tool_hook.rb` (16): `Style/ArgumentsForwarding` ×10 (linhas 6, 7, 15, 21, 24), `Metrics/AbcSize` + `Cyclomatic` + `Perceived` em `40:3`, `Rails/WhereExists` ×3 (37, 51, 57).
- `app/services/connecta/scope/installer.rb` (1): `2:1 Metrics/ModuleLength [101/100]`.
- `app/services/connecta/scope/presence_bulk_hook.rb` (3): `10:3 Metrics/CyclomaticComplexity`, `Metrics/PerceivedComplexity`, `24:5 Style/CombinableLoops`.
- `app/services/connecta/scope/socket_hook.rb` (3): `4:1 Metrics/ModuleLength [104/100]`, `79:3 Metrics/CyclomaticComplexity`, `Metrics/PerceivedComplexity`.
- `app/services/connecta/transfer/local_transaction.rb` (8): `9:1 Metrics/ClassLength [189/175]`, `35:7 Rails/TransactionExitStatement`, `91:3 Metrics/AbcSize`, `Metrics/CyclomaticComplexity`, `Metrics/MethodLength [34/19]`, `Metrics/PerceivedComplexity`, `93:7 Style/RedundantBegin`, `230:26 Lint/UnusedMethodArgument [warning]`.
- `spec/connecta/attachment_download_scope_spec.rb` (14): `Lint/ConstantDefinitionInBlock` ×2 + `RSpec/LeakyConstantDeclaration` ×2 (25–26), `RSpec/InstanceVariable` ×9 (67, 323, 324, 326, 355, 356, 389, 403), `Layout/HashAlignment` ×1 (168:34).
- `spec/connecta/captain_scope_spec.rb` (1): `241:30 Layout/HashAlignment`.
- `spec/connecta/scope_b1_leftovers_spec.rb` (17): `RSpec/MultipleMemoizedHelpers` ×13, `RSpec/LetSetup` ×1 (51:3), `Lint/AmbiguousBlockAssociation` ×2 (376:9, 385:7), `Layout/HashAlignment` ×1 (436:58).
- `spec/connecta/scope_team_contact_spec.rb` (10): `17:1 RSpec/MultipleDescribes`, `63:43 Rails/WhereExists`, `172:48 Layout/HashAlignment`, `201:39 Lint/RedundantCopDisableDirective [warning]`, `Style/RedundantConstantBase` ×3 (266, 267, 332), `RSpec/ContainExactly` ×2 (272, 322).
- `spec/connecta/transfer_cutover_spec.rb` (1): `119:7 RSpec/ExampleLength [56/50]`.
- `spec/connecta/transfer_integration_spec.rb` (5): `Lint/AmbiguousBlockAssociation` ×4 (91, 102, 134, 147–148).

### Ofensas por cop (todas)

13 `RSpec/MultipleMemoizedHelpers`, 10 `Style/ArgumentsForwarding`, 9 `RSpec/InstanceVariable`, 7 `Lint/AmbiguousBlockAssociation`, 6 `Metrics/CyclomaticComplexity`, 6 `Metrics/PerceivedComplexity`, 5 `Rails/WhereExists`, 4 `Metrics/AbcSize`, 4 `Style/RedundantConstantBase`, 4 `Layout/HashAlignment`, 2 `RSpec/LeakyConstantDeclaration`, 2 `Lint/ConstantDefinitionInBlock`, 2 `Metrics/ModuleLength`, 2 `RSpec/ContainExactly`, 1 `RSpec/LetSetup`, 1 `RSpec/MultipleDescribes`, 1 `Lint/RedundantCopDisableDirective`, 1 `RSpec/ExampleLength`, 1 `Lint/UnusedMethodArgument`, 1 `Style/RedundantBegin`, 1 `Metrics/MethodLength`, 1 `Rails/TransactionExitStatement`, 1 `Metrics/ClassLength`, 1 `Style/CombinableLoops`, 1 `Layout/TrailingEmptyLines`, 1 `Style/MultilineIfModifier`, 1 `Style/SoleNestedConditional`, 1 `Style/MutableConstant`. Total 90.

## 6. Whitespace

- `git diff --check` (rastreado): limpo, exit 0 — mas **não cobre arquivos não rastreados** (todos os G0 são `??`).
- Não rastreados, read-only, sem `git add`: `git diff --no-index --check /dev/null <arquivo>` por arquivo. Semântica dos códigos: o diff de um arquivo novo contra `/dev/null` sempre sai com exit 1 (há diff); o que prova whitespace é **saída de warning**, não o exit. Exit 0 + sem saída = limpo seria só para arquivos idênticos (impossível contra /dev/null); exit 1 sem saída = sem erro de whitespace; exit 1 com saída = erro real.
- Resultado nos 73 Ruby vivos do G0 (`app/services/connecta/scope/*.rb`, `transfer/*.rb`, `spec/connecta/*.rb` + `support/*.rb`, `spec/requests/connecta/*.rb`, `spec/support/connecta/*.rb`): **1 warning real** — `app/services/connecta/scope/copilot_hook.rb:21: new blank line at EOF` (mesma ofensa que o RuboCop `Layout/TrailingEmptyLines` acima). Os outros 72 sem saída.
- Cópias de baseline/snapshot sob `.context/evidence/g0/*/` (ex.: `03-baseline-arquivos/`) são histórico, não código vivo — excluídas desta contagem.
- `29-logs/` (8 arquivos desta tarefa): todos limpos, sem saída de warning.
- Avisos em logs antigos (histórico, não código): `26-logs/escopo-lote-a-1.log:137-138 trailing whitespace`, `escopo-lote-a-2.log:196`, `escopo-lote-b-1.log:431`, `escopo-lote-b-2.log:66`, `28-logs/anexos-final-3.log:50`, `anexos-final-4.log:38` new blank line at EOF. Preservados como estão.

## 7. Infraestrutura e preservação

Disponível em todos os comandos; nenhuma recriação/modificação de infra, banco ou schema.
Nenhuma escrita manual de banco. `git status --short`: só os 7 grupos `??` pré-existentes
(`.context/`, `app/services/connecta/scope/`, `transfer/`, `scripts/`, `spec/connecta/`,
`spec/requests/connecta/`, `spec/support/connecta/`); nenhum rastreado modificado.
Sem `ruby -c` como substituto de prova; sem repetição além das 3 Captain autorizadas.

## 8. Matriz final arquivo → log da validação atual

| Spec | Log atual | Ex |
|---|---|---|
| transfer_cutover + activation + outbound_dispatch + transfer_integration | `25-validacao-transferencia.md` / `25-logs/transfer-final-1.log` | 40/0 |
| captain_scope | `29-logs/captain-run-{1,2,3}.log` (3×33/0) + `26-logs/escopo-lote-a-2.log` | 33/0 ×3 |
| attachment_download_scope | `28-logs/anexos-final-4.log` | 27/0 |
| b1_leftovers + team_contact + b2_complements | `26-logs/escopo-lote-b-2.log` | 73/0 |
| policy_query + http_filter + socket | `29-logs/g1-lote-1.log` | 94/0 |
| related_http + notifications + internal_chat + agent_bot + attachment_access + route_inventory + smoke | `29-logs/g2-lote-1.log` | 123 ex, 6 falhas (§3) |

Soma executada nesta tarefa: 94 + 123 + 99 (3×33) = 316 exemplos. Com os verdes já obtidos (40 + 27 + 73): cobertura G0 = 19/19 specs, 456 exemplos totais (40 + 33 + 27 + 73 + 94 + 123 + 3×33 − 33 captain já contado em 26A2 = conta simples por execução: cada spec tem pelo menos um log verde exceto as 6 falhas G2).
