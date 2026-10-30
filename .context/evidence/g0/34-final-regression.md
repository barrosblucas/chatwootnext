# 34 — Regressão final G0 (TASK_ID g0-final-regression) — 8 comandos, 19 specs, 0 falhas

Somente o autorizado: 1 disable local em `socket_hook.rb` + check estático + 8 lotes pela fila.
Nenhum outro código/spec/runner/config alterado durante os 8 comandos. Sem retry, sem SQL manual,
sem teardown, sem segredos impressos.

## 1. Tabela dos 8 comandos (resultado REAL, uma execução cada, sem retry)

| # | Label | Comando (padrão exato: PATH + flock + timeout 300 + launcher) | Log | Exit | Tempo | Ex | Fa |
|---|---|---|---|---|---|---|---|
| 1 | T | `... flock -w 900 .../spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/transfer_cutover_spec.rb spec/connecta/transfer_activation_spec.rb spec/connecta/outbound_dispatch_spec.rb spec/connecta/transfer_integration_spec.rb` | `34-logs/t-transfer.log` | 0 | 45s | 40 | 0 |
| 2 | D | `... --spec --apply spec/connecta/attachment_download_scope_spec.rb` | `34-logs/d-attachment.log` | 0 | 28s | 27 | 0 |
| 3 | B | `... --spec --apply spec/connecta/scope_b1_leftovers_spec.rb spec/connecta/scope_team_contact_spec.rb spec/connecta/scope_b2_complements_spec.rb` | `34-logs/b-leftovers.log` | 0 | 70s | 73 | 0 |
| 4 | G1 | `... --spec --apply spec/connecta/scope_policy_query_spec.rb spec/connecta/scope_http_filter_spec.rb spec/connecta/scope_socket_spec.rb` | `34-logs/g1-scope.log` | 0 | 86s | 94 | 0 |
| 5 | G2 | `... --spec --apply spec/connecta/scope_related_http_spec.rb spec/connecta/scope_notifications_spec.rb spec/connecta/internal_chat_scope_spec.rb spec/connecta/agent_bot_delivery_spec.rb spec/connecta/attachment_access_spec.rb spec/requests/connecta/route_inventory_spec.rb spec/connecta/transfer_schema_smoke_spec.rb` | `34-logs/g2-related.log` | 0 | 113s | 123 | 0 |
| 6 | C1 | `... --spec --apply spec/connecta/captain_scope_spec.rb` (1ª, sozinha) | `34-logs/c1-captain-1.log` | 0 | 27s | 33 | 0 |
| 7 | C2 | `... --spec --apply spec/connecta/captain_scope_spec.rb` (2ª, sozinha, seguida) | `34-logs/c2-captain-2.log` | 0 | 27s | 33 | 0 |
| 8 | C3 | `... --spec --apply spec/connecta/captain_scope_spec.rb` (3ª, sozinha, seguida) | `34-logs/c3-captain-3.log` | 0 | 25s | 33 | 0 |

Prefixo comum de todos (`...`): `cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH`.
Comando completo registrado no §1 de cada log (o runner imprime a linha; INICIO/FIM UTC no corpo).
Janela total: 2026-10-24T19:11:26Z → 19:19:02Z. TSV incremental:
`/home/thanos/chatwootnext-connecta-g0-prep/.context/evidence/g0/34-logs/manifest.tsv`
(label, exit, tempo, examples, failures, logpath — append imediato após cada comando, sem sobrescrita).

Somas (matriz do §2 manda) — CORREÇÃO de contagem (2026-10-24, sem reexecução; logs/TSV intactos):
40+27+73+94+123+33+33+33 = **456 execuções**; únicos **40+27+73+94+123+33 = 390 em 19 arquivos**.
O número 357 anterior excluía o Captain inteiro indevidamente. `captain_scope_spec.rb` conta **1× (33)
na unicidade (19º arquivo) e 3× (33 cada, C1+C2+C3 consecutivas e sozinhas no final) na execução**.

## 2. Matriz 19 arquivos → logs (nenhum omitido)

| Spec | Lote/log | Ex no lote |
|---|---|---|
| spec/connecta/transfer_cutover_spec.rb | T `t-transfer.log` | parte de 40/0 |
| spec/connecta/transfer_activation_spec.rb | T `t-transfer.log` | parte de 40/0 |
| spec/connecta/outbound_dispatch_spec.rb | T `t-transfer.log` | parte de 40/0 |
| spec/connecta/transfer_integration_spec.rb | T `t-transfer.log` | parte de 40/0 |
| spec/connecta/attachment_download_scope_spec.rb | D `d-attachment.log` | 27/0 |
| spec/connecta/scope_b1_leftovers_spec.rb | B `b-leftovers.log` | parte de 73/0 |
| spec/connecta/scope_team_contact_spec.rb | B `b-leftovers.log` | parte de 73/0 |
| spec/connecta/scope_b2_complements_spec.rb | B `b-leftovers.log` | parte de 73/0 |
| spec/connecta/scope_policy_query_spec.rb | G1 `g1-scope.log` | parte de 94/0 |
| spec/connecta/scope_http_filter_spec.rb | G1 `g1-scope.log` | parte de 94/0 |
| spec/connecta/scope_socket_spec.rb | G1 `g1-scope.log` | parte de 94/0 |
| spec/connecta/scope_related_http_spec.rb | G2 `g2-related.log` | parte de 123/0 |
| spec/connecta/scope_notifications_spec.rb | G2 `g2-related.log` | parte de 123/0 |
| spec/connecta/internal_chat_scope_spec.rb | G2 `g2-related.log` | parte de 123/0 |
| spec/connecta/agent_bot_delivery_spec.rb | G2 `g2-related.log` | parte de 123/0 |
| spec/connecta/attachment_access_spec.rb | G2 `g2-related.log` | parte de 123/0 |
| spec/requests/connecta/route_inventory_spec.rb | G2 `g2-related.log` | parte de 123/0 |
| spec/connecta/transfer_schema_smoke_spec.rb | G2 `g2-related.log` | parte de 123/0 |
| spec/connecta/captain_scope_spec.rb | C1+C2+C3 `c1/c2/c3-captain-*.log` | 33/0 ×3 |

## 3. Destaques diagnósticos (sem correção nesta tarefa — nada a corrigir)

- G2 **123/0**: as 6 falhas da tarefa 29 (`scope_related_http:368/375/382/389/396` + `route_inventory:204`)
  NÃO se repetiram. Causa provável (não afirmada como prova): correção inbox da evidência 30
  (gate restaurado no `fetch_inbox`) + inventário da frente 31 (rota de download classificada)
  agora revalidados em spec pela primeira vez — mas nenhum diff foi feito aqui para isolar a causa.
- Captain 3× **33/0 cada**, consecutivas e sozinhas no final, sem flake entre runs.
- Zero exemplos = não-sucesso: não ocorreu (todos os lotes reportaram `N examples` > 0).
- Nenhum comando precisou de retry; nenhum log foi sobrescrito (nomes novos em `34-logs/`;
  dados anteriores em 21/26/28/29/31/32/33-logs preservados).

## 4. Estático (AC1) — executado ANTES dos 8 lotes, Ruby estável durante

- Única edição de código: `app/services/connecta/scope/socket_hook.rb` — par local
  `# rubocop:disable Metrics/ModuleLength` (linha 7, após comentário de coesão de
  roteamento/escopo/snapshot/admin) + `# rubocop:enable Metrics/ModuleLength` (fim).
  Precedente seguido: `installer.rb:4/128`. Nenhum executável alterado, nenhum global.
- Full RuboCop check-only `env -i` Ruby 3.4.4 + BUNDLE do launcher, 73 arquivos:
  **73 arquivos, 0 ofensas, EXIT 0**, stderr vazio.
  JSON: `/home/thanos/chatwootnext-connecta-g0-prep/.context/evidence/g0/33-logs/rubocop-final-4.json`.
  Envelope: `/home/thanos/chatwootnext-connecta-g0-prep/.context/evidence/g0/33-logs/rubocop-final-4.log`
  (INICIO_UTC 2026-10-24T19:11:06Z, DURACAO_REAL 2s). Stderr: `rubocop-final-4.stderr.log` (vazio).
- `ruby -c` 3.4.4 no socket pós-edição: `Syntax OK`. Whitespace
  `git diff --no-index --check /dev/null`: vazio. `git diff --check` (rastreado): limpo.
- Detalhe registrado no append 3 de
  `/home/thanos/chatwootnext-connecta-g0-prep/.context/evidence/g0/33-scope-lint.md` (§§16-17).

## 5. Guarda-infra (antes dos lotes; sem matar/apagar)

- `df -h /tmp`: tmpfs 7,6 GB, 5,1 GB usados (67%), 2,6 GB livres.
- `flock -n .../spec.lock true`: livre. `ps`: nenhum `g0_test_env.sh`/`rspec` residual
  além do próprio harness/opencode.

## 6. Pendências (finitas, fora deste escopo)

1. Dossiê 35: NÃO feito (próxima tarefa documental, vedado aqui).
2. Causa isolada do verde G2: nenhum bisect/diff executado aqui (não exigido pelo briefing).
3. Runtime/infra além dos 8 lotes (servidor/produção/QR): intocado por escopo.

## 7. Fontes

- `.context/README.md` — orientação.
- `.context/evidence/g0/33-logs/rubocop-final-3.json` — 73/1 de partida (só ModuleLength socket).
- `.context/evidence/g0/29-regressao-lint.md` — matriz 19 + comandos G1/G2/Captain anteriores.
- `.context/evidence/g0/30-correcoes-inbox.md` — 5 guards inbox revalidados agora no G2.
- `.context/evidence/g0/31-spec-lint.md` — 5 specs + inventário revalidados agora (D/B/C/G2).
- `.context/evidence/g0/32-transfer-lint.md` — `next WAIT` revalidado agora no T.
- `.context/evidence/g0/22-quadro-evidencias.md` — R-G0-LOCAL-1; QR/produção adiados (não alterado).
