# T0.2 parte B1 — filtros, HTTP de mensagens e criação de conversa na inbox marcada (G0, 2026-10-22)

**Estado: PARCIAL.** T0.2 segue ABERTO. G0 segue ABERTO. Esta parte cobre o filtro `POST conversations/filter`, a lista e contagens, as superfícies HTTP de conversa e mensagens, e a criação de conversa na mesma inbox física WhatsApp. Socket, anexos (download), contatos, busca global, notificações, reports/export, integrações e QR/status detalhados ficam para B2/B3. Transferência local (T0.3) não foi tocada.

Autorização: citação do briefing (alvo local `conecta-baileys-g0-test`, banco `conecta_baileys_g0_test`, Postgres `127.0.0.1:55432`, Redis `127.0.0.1:56379`). Sem dado real, sem produção, sem remoto, sem alteração de `db/schema.rb`, Gemfile, controllers, policies ou runner, sem teardown, sem commit.

## 1. Baseline (antes de editar)

- Hashes de 42 arquivos produtivos e do spike: `07-baseline-logs/sha256-antes.txt`.
- Spec da parte A antes de qualquer edição: **30 exemplos, 0 falhas** (runner oficial, Ruby 3.4.4 do cache, log em `~/.cache/connecta-g0-test/logs/07-baseline-spec.log`).
- Banco antes: último snapshot desta tarefa em `06-baseline-logs/state-depois.txt` (16:19:48Z): canário `g0-canario-sintetico-2026-10-22`, 185 migrações.

## 2. Lacunas comprovadas antes da correção

Spec novo rodado contra o código original (62 exemplos, 47 falhas no primeiro conjunto; 19 falhas no spec novo depois de corrigir um erro de fixture de mock do Redis):

- **Gestor editava mensagem**: `PATCH` e `DELETE` de mensagem por gestor (acompanhar) respondiam 200; `update`/`destroy` não tinham hook.
- **Gestor gravava rascunho**: `PUT draft_messages` por gestor respondia 200.
- **Transferência legada chegava ao I/O**: `POST connecta_transfer` na inbox marcada respondeu 500, o que indica chamada ao serviço legado.
- **Criação reabria origem**: agente A criou conversa usando só `source_id` da conversa dele; `Conversation.count` foi de 8 para 9 (`07-antes-fix-http.log`).
- **Admin com status de negação errado**: `toggle_status` do admin respondia 401 (devia 403); criação respondia 422 (devia 403).
- **Negações autenticadas viravam 401** (`Pundit::NotAuthorizedError` pelo rescue global), o que revela a existência da conversa.
- **Filtro POST**: nenhum vazamento de conversa de B para A, gestor ou membro foi reproduzido nos cenários testados (ver seção 4, AC1). A relação já passava pelo `FinderHook` via `base_relation`. O que faltava era a prova, e o admin recebia conteúdo da inbox marcada na listagem.

## 3. Mudanças

| Arquivo | Mudança |
|---|---|
| `app/services/connecta/scope/conversation_http_hook.rb` (novo) | Hook único prepended em `ConversationsController` e `Conversations::BaseController`: leitura negada → 404; escrita negada (qualquer não-GET) → 403; criação negada antes de I/O → 403; transferência legada negada → 403; handler `connecta_scope_denied`. |
| `app/services/connecta/scope/denied.rb` (novo) | Erro de negação com status (`not_found`, `forbidden`). |
| `app/services/connecta/scope/installer.rb` | Instala o hook, o `rescue_from`, o guard de escrita genérico, o guard de criação (`prepend_before_action`) e o guard de transferência. |
| `app/services/connecta/scope/conversation_query.rb` | Admin nominal não recebe linhas da inbox marcada na listagem. A auditoria `list` continua, com `conversation_id` nulo (metadado). |
| Removidos (spike, não versionados): `conversation_write_hook.rb`, `message_write_hook.rb`, `assignment_write_hook.rb`, `write_guard.rb` | Substituídos pelo hook único. |
| `spec/connecta/support/g0_scope_fixture.rb` (novo) | Fixture compartilhado, extraído da parte A sem mudar entidades. |
| `spec/connecta/scope_policy_query_spec.rb` | Usa o fixture; 30 exemplos mantidos; expectativas alinhadas: leitura negada 401→404, escrita negada 401→403, admin sem conteúdo da inbox marcada na lista. Nenhuma negação foi enfraquecida. |
| `spec/connecta/scope_http_filter_spec.rb` (novo) | 32 exemplos (filtro, mensagens, rascunho, participantes, etiquetas, prioridade, agendamento, transferência, origem, criação, 401, admin). |
| `.context/decisions/002-negacao-http-escopada-g0.md` (novo) | Decisão: 404 leitura, 403 escrita e criação, 401 nativo para não autenticado. |

Arquivos produtivos conferidos por hash (antes e depois): controllers de conversa, `conversation_policy.rb`, `filter_service.rb`, `conversations/filter_service.rb`, `permission_filter_service.rb`, `conversation_finder.rb`, `config/routes.rb`, `db/schema.rb`, `Gemfile.lock`, `scripts/connecta/g0_test_env.sh`. **Nenhum mudou** (`07-baseline-logs/sha256-depois.txt`). `git diff --check` limpo nos rastreados; nenhum arquivo rastreado foi alterado.

## 4. Resultados reais por critério

**AC1 — filtro e contagens** (`scope_http_filter_spec.rb`, grupo de filtro):
- Agente A, `POST filter` status open: payload A, A1 e controle; `all_count` 3.
- Agente B, composto com `OR` no `display_id` de A: só a conversa de B; `all_count` 1.
- Agente B, `display_id` de A: payload vazio; `all_count` 0.
- Agente B, `actor_id`, `org_unit_id`, `sector`, `user_id` e `X-Connecta-*` forjados: só a conversa de B; `all_count` 1.
- Filtro salvo global criado pelo admin (`display_id` de B), usado pelo agente A: vazio; 0.
- Gestor A: A e A1 (`all_count` 2). Membro sem grant: vazio (0). Admin: vazio (0).
- Paginação com `CONVERSATION_RESULTS_PER_PAGE=1`: três páginas com A, A1 e controle, sem vazamento.
- Agente B, `meta` `all_count` 1; `search` por texto de A: vazio.

**AC2 — mensagens, ações e criação**:
- `GET messages` de A: 200. De B: 404, sem o conteúdo. Gestor: GET 200, POST 403, sem gravar. Gestor `PATCH` e `DELETE`: 403, mensagem intacta. Membro sem grant: 404 (GET e POST), sem gravar.
- Agente A com `assignee` B na conversa: envia (200, +1 mensagem). Operação não depende do assignee.
- `transferring`: GET 200, POST 403. `case_version` 0: GET 200, POST 403. `pending_activation` e `activation_stuck`: GET e POST 404, sem gravar.
- Rascunho: agente A grava (200); B lê 404; gestor grava 403.
- Gestor: participante 403 sem alterar `ConversationParticipant`; etiqueta, prioridade e agendamento 403 sem alterar. Agente A altera prioridade (200).
- Transferência legada: `POST connecta_transfer` e `GET destinations` na inbox marcada → 403; `Connecta::TransferService.new` não é chamado (`not_to receive`).
- Origem: conversa transferida reaberta por `toggle_status`, `PUT` e `assignments` do agente A → 404; status `resolved` e `assignee` nil mantidos. `transferring` com `status: open` → 403, status mantido.
- Criação: agente A por `inbox_id` + `status: open` → 403, sem criar, com auditoria `conversation_create` deny. Agente A por `source_id` → 403, sem criar. Admin → 403. Inbox não marcada (controle): agente A cria (200, +1).

**AC3 — semântica HTTP e admin**:
- Autenticados: 404 em leitura negada; 403 em escrita negada. Nenhuma negação autenticada responde 401 em inbox marcada.
- Não autenticados: lista, detalhe, mensagens, filtro, envio e criação → 401, sem gravar.
- Admin: `GET messages` de A → 200, com auditoria `detail` allow por conversa. `toggle_status` → 403, com auditoria `conversation_toggle_status` deny, status mantido. Listagem → vazia, com auditoria `list` (metadado).
- Controle nativo (inbox não marcada): agente não membro continua 401 (nativo).

**AC4 — sem I/O externo e sem alteração produtiva**:
- Nenhuma chamada HTTP externa. Os hooks só são instalados em `Rails.env.test?`.
- Banco depois (`07-baseline-logs/state-depois.txt`): canário preservado; 185 migrações; 119 tabelas base e 2 views (112 da evidência 06 + 7 `connecta_g0_*`); zero linhas em tabelas de negócio e no spike.

## 5. Validação

| Execução | Resultado |
|---|---|
| `scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_policy_query_spec.rb` (baseline, antes de editar) | 30 exemplos, 0 falhas |
| Mesmo launcher, dois specs, código original (antes da correção) | 62 exemplos, 47 falhas (`07-antes-fix.log`) |
| Spec novo, código original, depois do ajuste do fixture | 32 exemplos, 19 falhas (`07-antes-fix-http.log`) |
| Mesmo launcher, dois specs, código corrigido | 62 exemplos, 0 falhas |
| Combinado final: scope A + scope B1 + `spec/requests/connecta/route_inventory_spec.rb` (T0.1) + `agent_bot_delivery_spec.rb` e `attachment_access_spec.rb` (T0.4/T0.5) | **96 exemplos, 0 falhas**, 1 min 12 s (`07-final-combinado.log`) |
| RuboCop (`env -i`, Ruby 3.4.4) em `app/services/connecta/scope/`, `app/services/conversations/` e specs de escopo | 43 arquivos, sem ofensas |
| `git diff --check` (rastreados) e busca de espaço no fim de linha (novos) | limpo |

Logs brutos ficam em `~/.cache/connecta-g0-test/logs/` (fora do repo); resumo em `07-logs/resumo-execucoes.txt`.

## 6. Remanescentes (não fechados)

- **T0.2 segue ABERTO.** Pendentes B2/B3: socket, download de anexos, contatos, busca global, notificações, reports/export, integrações, QR/status detalhados.
- **`GET conversations/unread_counts` não passa pelo escopo.** É um contador próprio com cache no Redis (`app/services/conversations/unread_counts/counter.rb:23-40`). A flag `conversation_unread_counts` está desligada por padrão (`config/features.yml:28-30`); com a flag ligada, a contagem por inbox não respeita grant. Sem teste. Não está incluído na afirmação de AC1 para contagens.
- **Superfícies de conversa cobertas só pelo guard genérico**, sem exemplo individual de negação: `scheduled_messages` (GET/update/destroy), `reactions`, `attachments#update`, `direct_uploads`, `recurring_scheduled_messages`, `custom_attributes`, `mute`/`unmute`, `transcript`, `presence_subscribe`, `update_last_seen`, `toggle_typing_status`, `unread`. O guard é fail-closed para qualquer não-GET; `filter` e `presence_subscribe_bulk` não têm conversa e não passam por ele.
- **Transferência legada negada para todos na inbox marcada**, inclusive para quem teria permissão, até o T0.3 entregar a transferência local. O guard `connecta_scope_transfer_guard!` precisa ser removido ou substituído pelo T0.3.
- **Criação negada para todos na inbox marcada**, inclusive admin. O fluxo de admissão (recepção) ainda não existe e é tarefa posterior.
- **Admin sem linhas da inbox marcada na lista** (decisão 002). Se o admin precisar de lista de metadados, a definição é nova decisão, com auditoria por página ou por conversa.
- **Mudança de status no spike**: 401→404/403 nas negações da parte A. Só vale nos hooks de teste.
- **Não executado nesta parte**: mutação com instalador desligado (já feita na parte A, não repetida); suíte ampla (sem necessidade pelo briefing); teardown (proibido).
