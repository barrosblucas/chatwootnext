# 33 — Scope lint parcial (TASK_ID g0-scope-lint) — ETAPA PARCIAL, SEM CHECK FINAL

Somente registro documental. Nenhum código/spec/lint/teste/build executado nesta tarefa. Sem aprovação inventada, sem check verde.

## 1. Cinco ajustes entregues parcialmente (outra etapa, sem check final)

Fonte: log anterior `/home/thanos/.local/state/opencode-coder/20261024T182929-1188051/report-final.txt` (STATUS BLOCKED após 5 arquivos, sem check final). Leitura atual só para confirmar presença do trecho (sem mutação):

- `app/services/connecta/scope/attachment_token.rb:7-8` — `PURPOSE`/`TTL` com `.freeze` (Style/MutableConstant).
- `app/services/connecta/scope/captain_http_hook.rb:8-12` — condicional aninhada fundida em `authorize_conversation` (Style/SoleNestedConditional).
- `app/services/connecta/scope/copilot_hook.rb:19-20` — blank EOF removido (Layout/TrailingEmptyLines).
- `app/services/connecta/scope/conversation_http_hook.rb:30-31` — guard clause em `connecta_scope_team_guard!` (Style/MultilineIfModifier).
- `app/services/connecta/scope/active_storage_guard.rb:42-44` — `exists?` direto (Rails/WhereExists).

`copilot_tool_hook.rb` NÃO lido nem tocado nesta tarefa (outro Coder ativo; ownership da tarefa atual veda leitura/mutação desse arquivo).

## 2. NÃO executado pelo coder anterior (pendência herdada)

- `ruby -c` / RuboCop final 73 arquivos: not run (interrompido antes do check final).
- `git diff --check` / whitespace 73 vivos: not run (pendente).
- Specs: not run (vedado no briefing da etapa anterior).
- Doc 33 + changelog desta tarefa: pendentes até este registro (33 agora criado; changelog em append separado).

## 3. Restam (sem check final, sem aprovação)

- `app/services/connecta/scope/copilot_tool_hook.rb` (16 ofensas no JSON 29; outra frente).
- `app/services/connecta/scope/attachment_downloads_controller.rb` (3 métricas).
- `app/services/connecta/scope/attachment_url_hook.rb` (3).
- `app/services/connecta/scope/presence_bulk_hook.rb` (3).
- `app/services/connecta/scope/socket_hook.rb` (3).
- `app/services/connecta/scope/installer.rb` (1).
- Check final 73 Ruby + whitespace: pendente (nenhum lint/teste nesta tarefa).
- Revalidação funcional pendente (frentes 31/32 zeradas; 40 ex Transfer + 27 anexos + Captain 3× aguardam validador pós-frentes).

## 4. Fontes

- `.context/README.md` — orientação.
- `.context/evidence/g0/29-regressao-lint.md` — 90 ofensas originais, partes já zeradas em 31/32.
- `.context/evidence/g0/31-spec-lint.md` — 5 specs zerados.
- `.context/evidence/g0/32-transfer-lint.md` — 11 arquivos Transfer zerados.
- Log anterior `/home/thanos/.local/state/opencode-coder/20261024T182929-1188051/report-final.txt` — STATUS BLOCKED após 5 arquivos sem check final.

---

# 33 (append) — Consolidado final (TASK_ID g0-final-static-check) — check final executado, 73 NÃO zerado

Somente o escopo autorizado: exceção local no `installer.rb` + check estático final dos 73 Ruby vivos.
NENHUM spec executado. Nenhuma refatoração nova além da exceção local. Nenhum outro código editado.

## 5. Exceção local Installer (única edição de código desta tarefa, AC1)

- Arquivo: `app/services/connecta/scope/installer.rb` (untracked `??`, fora de `git diff --stat` rastreado).
- Antes: `installer.rb:2 Metrics/ModuleLength [101/100]` (última ofensa restante do log `20261024T184243-1235933`).
- Depois: par de disable local `Metrics/ModuleLength` com justificativa curta no próprio arquivo:
  `# rubocop:disable Metrics/ModuleLength` (linha 4) + `# rubocop:enable Metrics/ModuleLength` (fim).
  Justificativa registrada no código: bootstrap coeso e idempotente dos hooks (registros por área +
  rota de download desenhada uma vez); fatiar o módulo espalharia install!/guards de segurança e pioraria
  a clareza sem reduzir acoplamento real.
- Nenhum registro removido, nenhum callback reordenado, nenhuma mudança de hook/segurança.
  Nenhum disable global/all. Nenhum outro arquivo editado nesta tarefa.

## 6. RuboCop final 73 Ruby (check-only, `env -i` + BUNDLE do launcher, Ruby 3.4.4, sem autocorrect)

Comando (caminhos absolutos, receita `scripts/connecta/g0_test_env.sh:47-49` + `gotchas.md:43`):

```sh
env -i PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:/usr/bin:/bin HOME="$HOME" LANG=C.UTF-8 BUNDLE_GEMFILE=/home/thanos/chatwootnext-connecta-g0-prep/Gemfile BUNDLE_PATH=/home/thanos/chatwootnext-connecta-g0-prep/.bundle/gems BUNDLE_FROZEN=true bundle exec rubocop --format json --out /home/thanos/chatwootnext-connecta-g0-prep/.context/evidence/g0/33-logs/rubocop-final-2.json app/services/connecta/scope app/services/connecta/transfer spec/connecta spec/requests/connecta spec/support/connecta
```

- Resultado factual: **73 arquivos, 2 ofensas**, EXIT 1, stderr vazio.
  JSON: `.context/evidence/g0/33-logs/rubocop-final-2.json`.
  Run: `.context/evidence/g0/33-logs/rubocop-final-2.log` (INICIO_UTC 2026-10-24T19:01:25Z na 1ª passada
  com 3 ofensas incluindo auto-falta de enable; re-passada pós-enable com 2 ofensas — log sobrescrito
  pela re-passada final). Stderr: `.context/evidence/g0/33-logs/rubocop-final-2.stderr.log` (vazio).
- 73 NÃO zerado — NÃO afirmar zero. Lista exata restante (fora do escopo desta tarefa, NÃO editadas):
  1. `app/services/connecta/scope/inbox_hook.rb:27:3 Metrics/AbcSize [convention]`
     (método `fetch_inbox` — gate da inbox marcada restaurado por outra frente em
     `.context/evidence/g0/30-correcoes-inbox.md`; outro ownership, intocado aqui).
  2. `app/services/connecta/scope/socket_hook.rb:34:151 Layout/LineLength [convention]`
     (linha `CONVERSATION_EVENTS.each ...` com 153 chars — arquivo de outra frente, intocado aqui).

## 7. Ruby -c 3.4.4 (73 vivos) + whitespace — AMBOS VERDES, SÓ COUNT/FALHAS

- `ruby -c` com `/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby`
  (binário confirmado `ls -l`, `ruby 3.4.4 +PRISM`): **pass=73 fail=0 total=73**.
  Nenhum `Syntax OK` individual colado no chat/doc — só o count.
- Whitespace vivos `git diff --no-index --check /dev/null <cada Ruby vivo>`:
  **arquivos-com-warning=0 total=73** (saída vazia nos 73; exit 1 aqui só diz que há diff contra /dev/null,
  semântica registrada em `29-regressao-lint.md` §6).
- `git diff --check` (rastreado): limpo. `git status --short`: só os 7 grupos `??` pré-existentes.
- Resumo guardado em `.context/evidence/g0/33-logs/syntax-whitespace-summary.log` (counts + falhas, sem 73 OK).
- Whitespace em logs antigos é histórico, não formatado (preservado como está).

## 8. Supressões métricas locais (inventário factual nos 73)

Pares `disable/enable` com justificativa no código (bootstrap/coesão, sem mudar comportamento):

- `app/services/connecta/scope/installer.rb:4/128` — `Metrics/ModuleLength` (esta tarefa, §5).
- `app/services/connecta/scope/copilot_tool_hook.rb:41/64` —
  `Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity`
  em `connecta_scope_copilot_contact_denied?` (frente toolzero, log `20261024T183420-1205242`).
- `app/services/connecta/scope/attachment_downloads_controller.rb:27/43` —
  `Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity`
  em `connecta_scope_verify_token!` (frente 2-anexos, log `20261024T183939-1224906`).
- `app/services/connecta/scope/attachment_url_hook.rb:37/56` —
  `Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity`
  em `connecta_scope_authorized_url` (frente 2-anexos, log `20261024T183939-1224906`).
- `app/services/connecta/transfer/local_transaction.rb:9` (inline, classe) —
  `Metrics/ClassLength`; `:91/132` — `Metrics/AbcSize, Metrics/CyclomaticComplexity,
  Metrics/MethodLength, Metrics/PerceivedComplexity` em `commit_local!` (frente 32, evidência 32).

Outras supressões NÃO-métricas (inventário, sem juízo): `Rails/SkipsModelValidations`
(`local_transaction.rb:111/113`, `outbound_dispatch.rb:31/33,55/57`);
RSpec (`SpecFilePathFormat`, `MultipleMemoizedHelpers`, `LetSetup`, `DescribeClass`,
`MultipleDescribes`, `ExpectInHook`, `AnyInstance`, `ExampleLength`) nos specs listados por
`grep -rn rubocop:disable` (§9 da apuração desta tarefa, sem edição).

## 9. Etapas parciais consolidadas (fontes: logs do harness + evidências 29/31/32 + §1-4 acima)

- 5 primeiros arquivos (outra etapa, sem check final na época): `attachment_token.rb` freeze,
  `captain_http_hook.rb` condicional fundida, `copilot_hook.rb` blank EOF, `conversation_http_hook.rb`
  guard clause, `active_storage_guard.rb` `exists?` direto (log `20261024T182929-1188051`).
- `copilot_tool_hook.rb`: lint zerado via safe-auto + 3 WhereExists manuais + disable local de 3
  métricas com justificativa (log toolzero `20261024T183420-1205242`).
- 2 anexos: guardas `Metrics` locais em `verify_token!`/`authorized_url` (log `20261024T183939-1224906`,
  BLOCKED sem re-passada na época — re-passada final feita AGORA neste append, §6).
- presence/socket: guards extraídos/helpers sem fundir loops; restava `installer.rb 101/100`
  (log `20261024T184243-1235933`, BLOCKED — resolvido AGORA neste append, §5).
- Frentes 31 (5 specs) e 32 (Transfer 11 arquivos): zerados com logs próprios
  (`31-logs/spec-lint.json`, `32-logs/transfer-lint.json`), preservados, sem reedição.

## 10. Funcional ainda pendente (runtime, NÃO executado aqui)

- Specs G0 NÃO executados nesta tarefa (vedado no briefing): nenhuma prova funcional nova.
- Revalidação funcional pendente pós-frentes: frentes 31/32 zeradas aguardam validador;
  40 Transfer (evidência 25) + 27 anexos (28-logs) + 3× Captain (29-logs) + G1 94/0 + G2 6 falhas
  mapeadas (`scope_related_http:368/375/382/389/396` — correção inbox em `30-correcoes-inbox.md`
  NÃO validada em spec; `route_inventory:204` classificado na frente 31 sem execução).
- Runtime (DB/Redis/serviços/especs) continua pendente para o validador; este append é só estático.

---

# 33 (append 2) — 2 fixes aplicados, check final REAL 73 arquivos / 1 ofensa emergente (TASK_ID g0-final-static-check)

Somente o escopo autorizado: 2 arquivos de codigo + append documental + changelog. Nenhum spec executado. Sem refatoracao alem dos 2 fixes.

## 11. Fix 1 — `inbox_hook.rb` Metrics/AbcSize (AC1, sem mover auth)

- Arquivo: `app/services/connecta/scope/inbox_hook.rb` (untracked `??`).
- Ofensa resolvida: `inbox_hook.rb:27:3 Metrics/AbcSize [<2, 26, 6> 26.76/26]` no `fetch_inbox` (JSON `33-logs/rubocop-final-2.json`).
- Edicao: par de disable LOCAL so `Metrics/AbcSize` nesse metodo, com justificativa curta no proprio arquivo
  ("Fluxo coeso obrigatorio de autorizacao pos-fetch e pre-provedor + audit allow diferido:
  fatiar espalharia gate/auditoria sem reduzir acoplamento real.").
- Menor alteracao: nenhum check removido/relaxado, nenhuma ordem movida — `super`, 3 guards,
  gate nominal 403/404 + `deny`, pending `allow` diferido intactos. Nenhum disable global/all.
- Precedente local seguido: disables em par com justificativa (`attachment_downloads_controller.rb:27/43`,
  `attachment_url_hook.rb:37/56`, `installer.rb:4/128`).

## 12. Fix 2 — `socket_hook.rb` Layout/LineLength (AC1, sem mudar semantica)

- Arquivo: `app/services/connecta/scope/socket_hook.rb` (untracked `??`).
- Ofensa resolvida: `socket_hook.rb:34:151 Layout/LineLength [153/150]` (JSON `rubocop-final-2.json`).
- Edicao: linha unica `CONVERSATION_EVENTS.each { ... }` quebrada em bloco `do...end` de 3 linhas;
  iterator (`each`), ordem do hash, payload, `admin_metadata` e snapshot intactos.
- Nenhum rename, nenhum reordenamento, nenhum comportamento alterado.

## 13. RuboCop final REAL 73 Ruby (check-only, `env -i` + BUNDLE do launcher, Ruby 3.4.4, sem autocorrect) — 1 OFENSA EMERGENTE

Comando (caminhos absolutos, mesma receita do §6):

```sh
env -i PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:/usr/bin:/bin HOME=/home/thanos LANG=C.UTF-8 BUNDLE_GEMFILE=/home/thanos/chatwootnext-connecta-g0-prep/Gemfile BUNDLE_PATH=/home/thanos/chatwootnext-connecta-g0-prep/.bundle/gems BUNDLE_FROZEN=true bundle exec rubocop --format json --out /home/thanos/chatwootnext-connecta-g0-prep/.context/evidence/g0/33-logs/rubocop-final-3.json app/services/connecta/scope app/services/connecta/transfer spec/connecta spec/requests/connecta spec/support/connecta
```

- Resultado factual: **73 arquivos, 1 ofensa**, EXIT 1, stderr vazio.
  JSON: `.context/evidence/g0/33-logs/rubocop-final-3.json`.
  Run: `.context/evidence/g0/33-logs/rubocop-final-3.log` (INICIO_UTC 2026-10-24T19:05:23Z, DURACAO_REAL 2s).
  Stderr: `.context/evidence/g0/33-logs/rubocop-final-3.stderr.log` (vazio).
- As 2 ofensas do JSON-2 SUMIRAM (AbcSize inbox + LineLength socket resolvidas).
- Ofensa emergente UNICA (efeito colateral da quebra de linha mandatoria do Fix 2, +2 linhas no modulo):
  `app/services/connecta/scope/socket_hook.rb:4:1 Metrics/ModuleLength [102/100]`.
- AC2 (73 zerado) NAO atingido pelo limite de escopo desta tarefa (vedado 3o fix / novo disable fora dos 2 autorizados).
  Nao afirmado zero. Nenhum verde inventado.

## 14. Sintaxe + whitespace dos 2 alterados (AC2, pos-edicao)

- `ruby -c` 3.4.4 (binario `/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby`):
  `inbox_hook.rb` Syntax OK; `socket_hook.rb` Syntax OK.
- Whitespace `git diff --no-index --check /dev/null <alvo>`: saida vazia nos 2 (exit 1 aqui so diz que ha diff
  contra /dev/null, semantica do §7 — sem warning de whitespace).
- `git status --short`: so os 7 grupos `??` pre-existentes (`.context/`, `app/services/connecta/scope/`,
  `app/services/connecta/transfer/`, `scripts/`, `spec/connecta/`, `spec/requests/connecta/`, `spec/support/connecta/`).
- Outros 71 nao revalidados individualmente (73 previos verdes no JSON-2/summary do §7; briefing mandou pos-edicao dos 2 alvos).
- `df -h /tmp`: leitura (67%), sem apagar.

## 15. Funcional ainda pendente (runtime, NAO executado aqui)

- Specs G0 NAO executados (vedado no briefing). Runtime (DB/Redis/servicos/especs) continua pendente para o validador.
- Decisao pendente para proxima frente: `socket_hook.rb` 102/100 — disable local `Metrics/ModuleLength` em par
  (precedente `installer.rb:4/128`) OU reducao real de 2+ linhas sem tocar iterator/ordem/payload/metadata/snapshot.

---

# 33 (append 3) — Disable local socket + RuboCop final 73/0 (TASK_ID g0-final-regression)

Somente o autorizado: 1 par de disable local no `socket_hook.rb`, check final 73, sem outro código.

## 16. Fix único — `socket_hook.rb` Metrics/ModuleLength (AC1, sem mudar executável)

- Arquivo: `app/services/connecta/scope/socket_hook.rb` (untracked `??`).
- Ofensa resolvida: `socket_hook.rb:4:1 Metrics/ModuleLength [102/100]` (JSON `33-logs/rubocop-final-3.json`;
  efeito colateral da quebra de linha mandatória do append 2, +2 linhas no módulo).
- Edição: par de disable LOCAL só `Metrics/ModuleLength` —
  `# rubocop:disable Metrics/ModuleLength` (linha 7) + `# rubocop:enable Metrics/ModuleLength` (fim),
  com justificativa curta no próprio arquivo (roteamento coeso de eventos para escopo/snapshot/admin:
  Gate + snapshot pré-destroy + metadados de admin; fatiar espalharia roteamento/guards sem reduzir
  acoplamento real). Precedente local seguido: `installer.rb:4/128`.
- Nenhum executável alterado (só 3 linhas de comentário + 2 diretivas), nenhum disable global/all,
  nenhuma config global. Nenhum outro arquivo editado nesta tarefa.

## 17. RuboCop final 73/0 REAL (check-only, `env -i` + BUNDLE do launcher, Ruby 3.4.4, sem autocorrect)

Comando (caminhos absolutos, mesma receita dos §§6/13):

```sh
env -i PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:/usr/bin:/bin HOME=/home/thanos LANG=C.UTF-8 BUNDLE_GEMFILE=/home/thanos/chatwootnext-connecta-g0-prep/Gemfile BUNDLE_PATH=/home/thanos/chatwootnext-connecta-g0-prep/.bundle/gems BUNDLE_FROZEN=true bundle exec rubocop --format json --out /home/thanos/chatwootnext-connecta-g0-prep/.context/evidence/g0/33-logs/rubocop-final-4.json app/services/connecta/scope app/services/connecta/transfer spec/connecta spec/requests/connecta spec/support/connecta
```

- Resultado factual: **73 arquivos, 0 ofensas**, EXIT 0, stderr vazio.
  JSON: `.context/evidence/g0/33-logs/rubocop-final-4.json`.
  Envelope: `.context/evidence/g0/33-logs/rubocop-final-4.log`
  (INICIO_UTC 2026-10-24T19:11:06Z, EXIT 0, DURACAO_REAL 2s, FIM_UTC 2026-10-24T19:11:08Z).
  Stderr: `.context/evidence/g0/33-logs/rubocop-final-4.stderr.log` (vazio).
- `ruby -c` 3.4.4 pós-edição no socket: `Syntax OK`. Whitespace
  `git diff --no-index --check /dev/null` no socket: vazio (exit 1 = só há diff contra /dev/null,
  sem warning). `git diff --check` (rastreado): limpo. `git status --short`: só os 7 grupos `??`
  pré-existentes. Outros 72 não revalidados individualmente (73 verdes no JSON-4 cobrem).
- `df -h /tmp`: leitura (67%), sem apagar.
