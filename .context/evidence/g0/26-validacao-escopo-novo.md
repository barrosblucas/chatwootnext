# 26 — Validação de escopo novo (T0.2 captain/anexos/B1/team-contato/B2)

Validação consolidada SOMENTE diagnóstico. Nenhum código/spec/runner/config/schema alterado nesta tarefa.

## Pré-checagens (leitura, sem matar nada)

- `df -h /tmp`: tmpfs 7,6 GB, 5,1 GB usados (67%), 2,6 GB livres — antes e depois dos lotes.
- Runner G0 residual: nenhum processo `g0_test_env.sh` / `bundle exec rspec spec/connecta`
  em execução; só os processos do próprio harness/opencode desta tarefa (este `opencode run`
  TASK_ID g0-validate-scope-new). Nada foi morto.
- As 5 specs existem: `spec/connecta/{captain_scope,attachment_download_scope,scope_b1_leftovers,scope_team_contact,scope_b2_complements}_spec.rb`.
- Contagem estática por `grep -cE "^[[:space:]]*it[[:space:]]+'"`: captain 33, attachment 27,
  b1_leftovers 41, team_contact 20, b2_complements 12.

## Comandos (fila obrigatória, execução única cada, em série)

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/captain_scope_spec.rb spec/connecta/attachment_download_scope_spec.rb
```

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_b1_leftovers_spec.rb spec/connecta/scope_team_contact_spec.rb spec/connecta/scope_b2_complements_spec.rb
```

## Resultado

- Pré-condições do runner: 11/11 `ok` nos dois lotes (Docker local, Ruby 3.4.4, sem Dotenv
  na raiz, database.yml → 127.0.0.1:55432/conecta_baileys_g0_test, containers do projeto em
  execução, Postgres 55432 e Redis 56379 escutando, segredo sintético 0600, banco com schema
  esperado). Infraestrutura disponível; nenhuma recriação/modificação de infra, banco ou schema.
- LOTE A: RSpec **60 examples, 18 failures** (`Finished in 1 minute 0.65 seconds`, files 3.54 s).
  Exit **1**. Duração real (parede, incluindo pré-condições): **66 s**.
  INICIO_UTC 2026-10-24T17:23:41Z, FIM_UTC 2026-10-24T17:24:47Z.
  Log: `26-logs/escopo-lote-a-1.log`.
- LOTE B: RSpec **73 examples, 11 failures** (`Finished in 1 minute 3.11 seconds`, files 3.73 s).
  Exit **1**. Duração real (parede, incluindo pré-condições): **69 s**.
  INICIO_UTC 2026-10-24T17:24:49Z, FIM_UTC 2026-10-24T17:25:58Z.
  Log: `26-logs/escopo-lote-b-1.log`.
- Lote B foi executado mesmo com falhas no lote A (mapeamento das duas frentes, sem repetição).
- `git diff --check`: limpo (exit 0). `git status --short`: só os grupos não rastreados
  pré-existentes (`.context/`, `app/services/connecta/scope/`, `app/services/connecta/transfer/`,
  `scripts/`, `spec/connecta/`, `spec/requests/connecta/`, `spec/support/connecta/`); nenhum
  arquivo rastreado modificado.

## Casos reais por spec (o que passou × o que falhou)

| Spec | Examples executados | Falhas | Passaram (examples − falhas) |
|---|---|---|---|
| captain_scope_spec.rb | parte do LOTE A (total A = 60) | 10 | — |
| attachment_download_scope_spec.rb | parte do LOTE A (total A = 60) | 8 | — |
| LOTE A total | 60 | 18 | 42 |
| scope_b1_leftovers_spec.rb | parte do LOTE B (total B = 73) | 1 | — |
| scope_team_contact_spec.rb | parte do LOTE B (total B = 73) | 9 | — |
| scope_b2_complements_spec.rb | parte do LOTE B (total B = 73) | 1 | — |
| LOTE B total | 73 | 11 | 62 |

Casos verdes individuais não listados um a um (29 falhas abaixo são a enumeração completa;
o restante dos 133 exemplos passou sem falha registrada no log).

## Falhas arquivo:linha (todas, causa observável no log, sem correção nesta tarefa)

### LOTE A — captain (10)

- `spec/connecta/captain_scope_spec.rb:174` — esperava 404, resposta foi 500
  (copilot threads, agente B sem grant; nada sobre persistência/enqueue avaliado).
- `spec/connecta/captain_scope_spec.rb:186` — esperava 404, resposta foi 500
  (copilot threads, membro da inbox sem grant).
- `spec/connecta/captain_scope_spec.rb:198` — esperava 404, resposta foi 500
  (copilot threads, conversa inexistente na conta).
- `spec/connecta/captain_scope_spec.rb:209` — `CopilotThread.count` mudou 0, esperava 1
  (agente A com grant não criou thread nem enfileirou).
- `spec/connecta/captain_scope_spec.rb:220` — `CopilotThread.count` mudou 0, esperava 1
  (controle inbox não marcada também não criou thread).
- `spec/connecta/captain_scope_spec.rb:238` — esperava 404, resposta foi 500
  (copilot_messages, membro sem grant).
- `spec/connecta/captain_scope_spec.rb:249` — esperava 404, resposta foi 500
  (copilot_messages, agente B sem grant mesmo em thread própria).
- `spec/connecta/captain_scope_spec.rb:306` — GetConversation devolveu conteúdo da conversa
  (`Conversation ID: #1 / Channel: Whatsapp / ...`) em vez de `Conversation not found`
  (alvo alheio exposto à ferramenta).
- `spec/connecta/captain_scope_spec.rb:320` — GetContact devolveu atributos do contato
  (`Contact ID: #19008 ...`) em vez de `Contact not found` (alvo alheio exposto).
- `spec/connecta/captain_scope_spec.rb:334` — SearchContacts por nome do contato de A
  incluiu `Contact ID: #19020` no resultado de B (contato alheio exposto).

### LOTE A — anexos (8)

- `spec/connecta/attachment_download_scope_spec.rb:74` — esperava 200, resposta foi 404
  (agente A com grant não recebeu os bytes).
- `spec/connecta/attachment_download_scope_spec.rb:105` — esperava 401, resposta foi 404
  (sem autenticação a rota não chegou ao 401 nativo).
- `spec/connecta/attachment_download_scope_spec.rb:121` — auditoria `deny`
  (surface attachment, access_path attachment_download) mudou 0, esperava 1
  (token de outro usuário não gerou o registro esperado).
- `spec/connecta/attachment_download_scope_spec.rb:203` — esperava 200 dentro dos 5 minutos,
  resposta foi 404 (token válido na janela não serviu bytes).
- `spec/connecta/attachment_download_scope_spec.rb:288` — `data_url` veio
  `rails/active_storage/blobs/redirect/...` em vez da rota autorizada
  `/api/v1/accounts/.../connecta_attachments/.../download` (serialização não usa a rota).
- `spec/connecta/attachment_download_scope_spec.rb:301` — `thumb_url` veio
  `rails/active_storage/representations/redirect/...` em vez da rota autorizada com `thumb`.
- `spec/connecta/attachment_download_scope_spec.rb:316` — `inline_audio_url` veio
  `rails/active_storage/blobs/redirect/...nota.ogg?disposition=inline` em vez da rota autorizada.
- `spec/connecta/attachment_download_scope_spec.rb:369` — representation legada do thumb
  marcado: esperava 404, resposta foi 500.

### LOTE B — leftovers/team-contato/complementos (11)

- `spec/connecta/scope_b1_leftovers_spec.rb:141` — `NoMethodError: undefined method 'not_to'`
  (sintaxe `expect { ... }.not_to change(...).and not_to have_enqueued_job` inválida;
  exemplo de reactions do gestor não avaliou o comportamento).
- `spec/connecta/scope_team_contact_spec.rb:54` — `Redis::CommandError: ERR wrong number of
  arguments for 'lpush' command` via `auto_assignment/inbox_round_robin_service.rb:11`
  (`ensure_assignee_is_from_team` no setup; PATCH com team_id não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:94` — mesmo `lpush`/round-robin
  (POST assignments com team_id não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:134` — mesmo `lpush`/round-robin
  (POST bulk_actions com team_id não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:223` — mesmo `lpush`/round-robin via
  `auto_assignment_handler.rb:26` no factory `create` de conversa
  (`create_marked_linked_contact!`; snapshot sem PII não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:235` — mesmo `lpush`/round-robin no factory
  (broadcast com snapshot não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:258` — mesmo `lpush`/round-robin no factory
  (admin fora do snapshot não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:270` — mesmo `lpush`/round-robin no factory
  (controle sem vínculo não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:285` — mesmo `lpush`/round-robin no factory
  (misto marcado+desmarcado não avaliado).
- `spec/connecta/scope_team_contact_spec.rb:305` — mesmo `lpush`/round-robin no factory
  (destruição/broadcast locais sem rede não avaliados).
- `spec/connecta/scope_b2_complements_spec.rb:117` (asserção em `:122`) —
  auditoria `allow` (surface inbox, access_path inbox_update) contou 0, esperava 1:
  caracterização antiga de `inbox_update` não se confirmou (admin nominal com papel de
  agente recebe 401 do nativo e nenhum `allow` é gravado; comportamento real diverge da
  caracterização, sem correção nesta tarefa).

## Infraestrutura

Disponível nos dois lotes; nenhuma recriação/modificação de infra, banco ou schema.
Nenhuma escrita manual de banco. Código/spec preservados. Sem `ruby -c` como substituto
de prova; sem repetição de comando.

---

# SEGUNDA RODADA — pós-correções Captain/fixtures/anexos/B1/team-contato/B2 (TASK_ID g0-validate-scope-new)

Somente diagnóstico. Nenhum código/spec/runner/config/schema alterado nesta tarefa.
Primeira rodada e seus logs (`26-logs/escopo-lote-a-1.log`, `26-logs/escopo-lote-b-1.log`)
preservados acima, sem sobrescrita. Novos logs: `26-logs/escopo-lote-a-2.log`,
`26-logs/escopo-lote-b-2.log`.

## Pré-checagens (leitura, sem matar nada)

- `df -h /tmp`: tmpfs 7,6 GB, 5,1 GB usados (67%), 2,6 GB livres.
- Runner G0 residual: nenhum processo `g0_test_env.sh` / `bundle exec rspec spec/connecta`
  em execução; só os processos do próprio harness/opencode desta tarefa. Nada foi morto.
- As 5 specs existem (mtimes: captain 16:49, attachment 17:47, demais 17:31).
- `git diff --check` antes dos lotes: limpo (exit 0).

## Comandos (fila obrigatória, execução única cada, em série)

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/captain_scope_spec.rb spec/connecta/attachment_download_scope_spec.rb
```

```sh
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_b1_leftovers_spec.rb spec/connecta/scope_team_contact_spec.rb spec/connecta/scope_b2_complements_spec.rb
```

## Resultado

- Pré-condições do runner: 11/11 `ok` nos dois lotes (mesmas 11 da rodada 1).
  Infraestrutura disponível; nenhuma recriação/modificação de infra, banco ou schema.
- LOTE A: RSpec **60 examples, 18 failures** (`Finished in 1 minute 5.96 seconds`,
  files 3.91 s). Exit **1**. Duração real (parede, incluindo pré-condições): **71 s**.
  INICIO_UTC 2026-10-24T17:49:35Z, FIM_UTC 2026-10-24T17:50:46Z.
  Log: `26-logs/escopo-lote-a-2.log`.
- LOTE B: RSpec **73 examples, 0 failures** (`Finished in 1 minute 5.18 seconds`,
  files 4.38 s). Exit **0**. Duração real (parede, incluindo pré-condições): **72 s**.
  INICIO_UTC 2026-10-24T17:50:54Z, FIM_UTC 2026-10-24T17:52:06Z.
  Log: `26-logs/escopo-lote-b-2.log`.
- Lote B foi executado mesmo com falhas no lote A (mapeamento das duas frentes, sem repetição).
- `git diff --check` após os lotes: limpo (exit 0). `git status --short`: só os grupos
  não rastreados pré-existentes (`.context/`, `app/services/connecta/scope/`,
  `app/services/connecta/transfer/`, `scripts/`, `spec/connecta/`,
  `spec/requests/connecta/`, `spec/support/connecta/`); nenhum arquivo rastreado modificado.

## Casos reais por spec (2ª rodada)

| Spec | Examples executados | Falhas | Passaram (examples − falhas) |
|---|---|---|---|
| captain_scope_spec.rb | parte do LOTE A (total A = 60) | 0 | 33 (todas as 33 do arquivo, sem falha no log) |
| attachment_download_scope_spec.rb | parte do LOTE A (total A = 60) | 18 | 9 (27 − 18; 9 sem falha registrada no log) |
| LOTE A total | 60 | 18 | 42 |
| scope_b1_leftovers_spec.rb | parte do LOTE B (total B = 73) | 0 | — (nenhuma falha no log) |
| scope_team_contact_spec.rb | parte do LOTE B (total B = 73) | 0 | — (nenhuma falha no log) |
| scope_b2_complements_spec.rb | parte do LOTE B (total B = 73) | 0 | — (nenhuma falha no log) |
| LOTE B total | 73 | 0 | 73 |

Casos verdes individuais não listados um a um (as 18 falhas abaixo são a enumeração
completa da 2ª rodada; o restante dos 133 exemplos passou sem falha registrada no log).

## Falhas arquivo:linha — 2ª rodada (todas, causa observável no log, sem correção nesta tarefa)

### LOTE A — captain (0)

Nenhuma falha com `captain_scope` no log `26-logs/escopo-lote-a-2.log`. As 10 falhas
Captain da rodada 1 não se repetiram.

### LOTE A — anexos (18)

Padrão dominante: 17 das 18 retornaram HTTP 500 onde o spec esperava 200 (2 casos)
ou 404 (15 casos); a 18ª (auditoria `deny`) contou 0 em vez de 1. O log não registra
a classe/mensagem da exceção que gerou o 500 (só o status observado via
`have_http_status`); nenhuma investigação ampla nem alteração nesta tarefa.

- `spec/connecta/attachment_download_scope_spec.rb:74` (asserção em `:77`) —
  esperava 200, resposta foi 500 (agente A com grant não recebeu os bytes).
- `spec/connecta/attachment_download_scope_spec.rb:82` (asserção em `:87`) —
  esperava 404, resposta foi 500 (token de A com sessão de B).
- `spec/connecta/attachment_download_scope_spec.rb:91` (asserção em `:94`) —
  esperava 404, resposta foi 500 (agente B de outro setor com token próprio).
- `spec/connecta/attachment_download_scope_spec.rb:98` (asserção em `:101`) —
  esperava 404, resposta foi 500 (membro da inbox sem grant).
- `spec/connecta/attachment_download_scope_spec.rb:114` (asserção em `:117`) —
  esperava 404, resposta foi 500 (admin nominal sem leitura de detalhe).
- `spec/connecta/attachment_download_scope_spec.rb:127` (asserção em `:130`) —
  auditoria `deny` (surface attachment, access_path attachment_download) mudou 0,
  esperava 1 (token de outro usuário não gerou o registro esperado).
- `spec/connecta/attachment_download_scope_spec.rb:142` (asserção em `:153`) —
  esperava 404, resposta foi 500 (token com account_id de outra conta).
- `spec/connecta/attachment_download_scope_spec.rb:157` (asserção em `:168`) —
  esperava 404, resposta foi 500 (token com anexo de outra conversa marcada).
- `spec/connecta/attachment_download_scope_spec.rb:174` (asserção em `:184`) —
  esperava 404, resposta foi 500 (blob trocado após a emissão).
- `spec/connecta/attachment_download_scope_spec.rb:188` (asserção em `:193`) —
  esperava 404, resposta foi 500 (token adulterado, assinatura quebrada).
- `spec/connecta/attachment_download_scope_spec.rb:197` (asserção em `:200`) —
  esperava 404, resposta foi 500 (token ausente).
- `spec/connecta/attachment_download_scope_spec.rb:209` (asserção em `:214`) —
  esperava 200 dentro dos 5 minutos, resposta foi 500 (token válido na janela
  não serviu bytes; a parte "expirado há 6 min → negado" do mesmo exemplo não foi
  avaliada isoladamente no log).
- `spec/connecta/attachment_download_scope_spec.rb:226` (asserção em `:232`) —
  esperava 404, resposta foi 500 (epoch alterada após a emissão).
- `spec/connecta/attachment_download_scope_spec.rb:236` (asserção em `:242`) —
  esperava 404, resposta foi 500 (revogação local com token ainda válido).
- `spec/connecta/attachment_download_scope_spec.rb:246` (asserção em `:252`) —
  esperava 404, resposta foi 500 (epoch removida do banco, fail-closed).
- `spec/connecta/attachment_download_scope_spec.rb:260` (asserção em `:266`) —
  esperava 404, resposta foi 500 (conversa `transferred_out` com token válido).
- `spec/connecta/attachment_download_scope_spec.rb:270` (asserção em `:276`) —
  esperava 404, resposta foi 500 (grant revogado com token válido).
- `spec/connecta/attachment_download_scope_spec.rb:280` (asserção em `:286`) —
  esperava 404, resposta foi 500 (heartbeat vencido com token válido, Gate real).

### LOTE B — leftovers/team-contato/complementos (0)

Nenhuma falha no log `26-logs/escopo-lote-b-2.log` (`73 examples, 0 failures`).
As 11 falhas da rodada 1 (B1 `not_to`, 9× `lpush` team/contato, caracterização
`inbox_update`) não se repetiram — registrado como fato observado, sem alegar
causa além das correções documentadas na evidência 27.

## Infraestrutura (2ª rodada)

Disponível nos dois lotes; nenhuma recriação/modificação de infra, banco ou schema.
Nenhuma escrita manual de banco. Código/spec preservados. Sem `ruby -c` como substituto
de prova; sem repetição de comando; nenhum exemplo de sucesso alegado além das
contagens (133 examples totais: 60 + 73).
