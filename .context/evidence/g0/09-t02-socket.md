# T0.2-c1 — socket: eventos de conversa e mensagem (G0, 2026-10-23)

**Estado: c1 fechado para os eventos de conversa e mensagem da lista.** Três eventos fora da lista expõem dados sem filtro e precisam de decisão (seção 3). Nenhum código foi alterado nesta rodada: as três validações passaram com o código deixado pela execução anterior.

Autorização: briefing do orquestrador (T0.2-c1, banco `conecta_baileys_g0_test`, runner com lock `spec.lock`). Local, dados sintéticos. Sem commit, sem `--teardown`, sem `.env`.

## 1. Resultados desta execução

Todas pelo runner com o lock compartilhado (`flock -w 900 .../spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply <specs>`).

| Run | Specs | Exemplos | Falhas | Exit | Tempo | Log |
|---|---|---|---|---|---|---|
| (a) | `spec/connecta/scope_socket_spec.rb` | 12 | 0 | 0 | 40,9 s | `09-logs/run-7-a-socket.log` |
| (b) | `spec/connecta/scope_policy_query_spec.rb` (sozinha) | 30 | 0 | 0 | 1 min 24 s | `09-logs/run-8-b-policy-alone.log` |
| (c) | policy + `scope_http_filter_spec.rb` + `scope_related_http_spec.rb` + socket | 140 | 0 | 0 | 3 min 02 s | `09-logs/run-9-c-combined.log` |

Tempo abaixo de 300 s: a rodada (c) não foi dividida.

RuboCop (`env -i` com PATH do toolchain e `BUNDLE_GEMFILE`, `BUNDLE_PATH`, `BUNDLE_FROZEN` do launcher):
`app/services/connecta/scope/socket_hook.rb app/services/connecta/scope/installer.rb spec/connecta/scope_socket_spec.rb` → 3 arquivos, sem ofensas, exit 0. Log: `09-logs/rubocop-09-final.log`.

Rodadas anteriores (logs da execução anterior, não refeitas):

| Run | Specs | Exemplos | Falhas | Situação |
|---|---|---|---|---|
| run-1 | socket | 12 | 0 | `09-logs/run-1-socket.log` |
| run-2 | policy + http_filter | 64 | 2 | `09-logs/run-2-regressao-installer.log` (http_filter:166 e :362) |
| run-3 | socket | 12 | 0 | `09-logs/run-3-socket-final.log` |
| run-4 | policy + http_filter | 64 | 53 | `09-logs/run-4-regressao-installer-idle.log` (policy 25, http_filter 28) |
| run-5 | policy sozinha | 30 | 25 | `09-logs/run-5-policy-alone.log` |
| run-6 | policy + http_filter | 59 | 0 | `09-logs/run-6-regressao-installer-after-edits.log` |

Divergência não explicada: run-2 e run-4 contaram 64 exemplos para os mesmos dois arquivos que run-6 contou como 59. `scope_http_filter_spec.rb` tem mtime 22/10 16:49, anterior a run-6, então a diferença não vem de edição do arquivo. Hoje os dois somam 64 (30 + 34), e a rodada (c) confirma 140 = 30 + 34 + 64 + 12.

## 2. Eventos cobertos (código)

Mapa do hook: `app/services/connecta/scope/socket_hook.rb:9-18`. Cada `define_method` (`:20-29`) grava a conversa do evento em `IsolatedExecutionState` e chama `super`. O filtro é o `user_tokens` privado (`:33-38`), que só age se a inbox estiver marcada (`Projection.marked?`, `:35`). Admin (nominal ou nativo) é excluído (`:37`, `:42`). Quem passa é quem o `Gate#read?` aceita com `access_path: 'socket'` (`:44`).

Os eventos abaixo chamam `user_tokens` no listener (`app/listeners/action_cable_listener.rb`):

| Evento | Método (linha) | `user_tokens` (linha) | Coberto em spec |
|---|---|---|---|
| message.created | `message_created` (74-80) | :77 | sim (vários exemplos) |
| message.updated | `message_updated` (82-88) | :85 | sim (1) |
| first_reply.created | `first_reply_created` (138-144) | :141 | não |
| conversation.created | `conversation_created` (146-151) | :148 | não |
| conversation.read | `conversation_read` (153-158) | :155 | não |
| conversation.status_changed | `conversation_status_changed` (160-165) | :162 | não |
| conversation.updated | `conversation_updated` (167-175) | :169 | sim (1) |
| assignee.changed | `assignee_changed` (234-239) | :236 | não |
| team.changed | `team_changed` (241-246) | :243 | não |
| conversation.contact_changed | `conversation_contact_changed` (248-253) | :250 | não |
| scheduled_message.created / updated / deleted | `scheduled_message_*` (90-112) | :93, :101, :109 | não |
| recurring_scheduled_message.created / updated / deleted | `recurring_scheduled_message_*` (114-136) | :117, :125, :133 | não |

Total: 16 eventos no mapa. A spec (12 exemplos) prova message.created, message.updated e conversation.updated, mais revogação (grant e sessão) e controle de inbox não marcada. Os outros 13 eventos estão cobertos só pela leitura do código. Adicionar exemplos para eles ficou fora do escopo desta tarefa.

Não há vazamento para admin nem para membro sem grant nos eventos testados (`scope_socket_spec.rb:49-56`, exemplos de admin nominal, admin nativo e membro sem grant).

## 3. Eventos NÃO cobertos

| Evento | Onde | Destinatários hoje | Situação |
|---|---|---|---|
| conversation.typing_on / typing_off / recording | `action_cable_listener.rb:186-232`; tokens em `:303-312` (`user_tokens` em `:310`) | membros, admins nativos e contato | fora do mapa. **c2** (briefing) |
| contact.created / updated / merged / deleted / group_synced | `action_cable_listener.rb:255-288`; token `account_<id>` (`:299-301`) | stream `account_<id>` | **c2** (briefing) |
| conversation.unread_count_changed | `action_cable_listener.rb:177-184`; `user_tokens` em `:181`; flag `conversation_unread_counts` | membros e admins nativos | **não está na lista do briefing**. Payload é `{}` (`:183`), só sinal. **Decisão** |
| conversation.mentioned | `action_cable_listener.rb:290-295`; token direto `[user.pubsub_token]` (`:294`); disparado por `app/models/mention.rb:56` | só o usuário mencionado | **RISCO: não passa pelo filtro.** Payload = `conversation.push_event_data`. Não verifiquei se quem é mencionado precisa ter grant na inbox |
| notification.created / updated / deleted | `action_cable_listener.rb:4-30`; token direto (`:6`, `:12`, `:24`) | só o usuário da notificação | **não passa pelo filtro.** Payload `notification.push_event_data` (`app/models/notification.rb:64-80`, inclui `primary_actor`). Não verifiquei se traz dado de conversa sem grant |
| account.cache_invalidated | `action_cable_listener.rb:32-39`; `user_tokens` em `:34` | agents e admins | sem chave de conversa, cai no nativo. Payload só `cache_keys`. Fora de c1 |
| inbox.provider_connection_updated | `action_cable_listener.rb:41-72` | agents e admins (QR só admin) | evento de inbox, fora do escopo |

Mensagem para contato (`contact_tokens`, `action_cable_listener.rb:320-326`) entrega ao próprio contato a mensagem da conversa dele. Não é vazamento entre agentes.

**Ação pedida ao orquestrador:** decidir os três itens marcados acima antes de declarar o socket fechado. O `conversation.mentioned` é o mais sério, porque entrega `push_event_data` da conversa a um usuário que o Gate pode não liberar. Correção provável: um prepend que filtre a lista de tokens desses eventos por `socket_reader?`. Não implementei porque é uma decisão de desenho e está fora do briefing.

## 4. run-4 e run-5: reproduzidos em série?

**Não reproduzidos.** Depois de liberar o lock, (b) passou com 30/0 e (c) com 140/0, com os mesmos arquivos de run-4 e run-5.

Sintoma de run-5 (`09-logs/run-5-policy-alone.log`, primeira falha): agente A recebeu `actual collection contained: [1, 2, 3, 4, 5, 6]`. A lista não aplicou o escopo, como se a inbox não estivesse marcada naquele processo.

Horário (mtime dos logs, aproximado): run-4 gravado às 01:50 e run-5 às 01:52. Os diretórios `10-logs` e `11-logs` foram modificados entre 01:45 e 01:54, no mesmo intervalo em que outros Coders rodavam specs no mesmo banco (cita o briefing). Os logs não guardam PID nem comando dos outros processos, então a concorrência não é confirmada pelos logs.

Hipóteses checadas:
- **Ordem de instalação: descartada como causa única.** `scope_policy_query_spec.rb:9-10` chama `G0ScopeSchema.ensure!` e `Installer.install!` ao carregar o arquivo, antes de qualquer exemplo. Rodou sozinha com 30/0 em (b).
- **Cache em memória: descartado.** `Projection.marked?` não usa cache (`app/services/connecta/scope/projection.rb:1` e `:11`), então um estado de outro exemplo não fica preso no processo.
- **Limpeza de dados por outro processo: sem evidência.** Cada exemplo roda numa transação (`spec/rails_helper.rb:53`), e a marca da inbox é criada com `let!` dentro dela (`spec/connecta/support/g0_scope_fixture.rb:45`). Não há `delete`, `truncate` ou `destroy_all` nos helpers do G0 (`spec/connecta/support/`, `spec/support/connecta/`).

**Mecanismo: não identificado.** Para reabrir, se a falha reaparecer: registrar `ps` dos rspec em execução no momento, o `inbox_id` do exemplo e o conteúdo de `connecta_g0_scoped_inboxes`.

## 5. Não verificado

- Os 13 eventos do mapa sem spec (seção 2).
- Payload de notificação e de mention: não verifiquei quais campos de conversa saem sem grant (seção 3).
- Diferença de contagem run-6 (59) × run-2/run-4 (64), explicada na seção 1.

## 6. Sugestão de registro (gotchas.md, fora da ownership desta tarefa)

- 2026-10-23 — o escopo do socket cobre só os eventos listados em `socket_hook.rb:9-18`; mention, notificação e contagem não passam pelo `user_tokens` — evidência: `app/listeners/action_cable_listener.rb:290-295`, `:4-30`, `:177-184`.
- 2026-10-23 — rodadas com escopo inativo (listagem sem filtro) não reproduziram em série (run-8, run-9); mecanismo não identificado — evidência: `09-logs/run-5-policy-alone.log`, `09-logs/run-8-b-policy-alone.log`.

## 7. T0.2-c2a (2026-10-23): mention, contagem de não lidas e metadados de admin

**Estado: c2a fechado para os itens 1 a 3 do briefing.** Typing, presença e contato (c2b) e notificações (c5) ficam fora, como pedido. Código alterado nesta rodada; `git diff` de arquivos rastreados segue vazio (tudo em diretórios não rastreados).

### 7.1 Código

- `app/services/connecta/scope/socket_hook.rb:36-41` (`conversation_mentioned`): inbox marcada só envia a menção se `socket_reader?` (Gate, `access_path: 'socket'`). Mention chega direto ao token, sem `user_tokens`, por isso o filtro roda antes do listener.
- `socket_hook.rb:45-50` (`conversation_unread_count_changed`): com conversa, o `user_tokens` do hook filtra pelo Gate. Conversa apagada chega só com `conversation_data`, sem registro para o Gate: em inbox marcada não envia o sinal.
- `socket_hook.rb:69-75` (`broadcast`): tokens de agente seguem o broadcast nativo (já filtrados). Para admins, em eventos da lista `ADMIN_EVENTS` (`:21-27`) de inbox marcada, envia metadados por job próprio.
- `socket_hook.rb:78-83` (`admin_metadata`): campos enviados (ver 7.2).
- `socket_hook.rb:86-90` (`socket_admin_tokens`): admins = nativos da conta (`account.administrators`) + nominais (grant `admin_nominal`, aceito por `Projection#admin?`, que exige sessão verificada). Nominal não precisa ser membro da inbox.
- `app/services/connecta/scope/admin_metadata_broadcast_job.rb` (novo): entrega `{ event, data }` por token com `ActionCable.server.broadcast`, na fila `critical`. `installer.rb` não mudou: não há prepend novo.

**Por que job próprio.** `app/jobs/action_cable_broadcast_job.rb:26` relê `conversation.push_event_data` para `CONVERSATION_READ`, `CONVERSATION_UPDATED`, `TEAM_CHANGED`, `ASSIGNEE_CHANGED` e `CONVERSATION_STATUS_CHANGED`. Um payload reduzido enviado por esse job seria trocado pelo completo, com o conteúdo. O job nativo é core e está fora do escopo, então o spike usa job próprio. Para produção, o ajuste no job nativo continua pendente (ver 7.4).

### 7.2 Campos que o admin recebe (fonte: `socket_hook.rb:78-83`, `:74`)

| Eventos | Campos mantidos | Origem |
|---|---|---|
| `message.created`, `message.updated`, `first.reply.created` | `id` (id da mensagem), `conversation_id` (display_id), `account_id` | `data[:id]`, `conversation.display_id`, envelope |
| `conversation.created`, `.read`, `.status_changed`, `.updated`, `contact_changed`, `assignee.changed`, `team.changed` | `id` (display_id, igual ao `id` do payload nativo em `app/presenters/conversations/event_data_presenter.rb:9`), `inbox_id`, `status`, `org_unit_id` (setor), `account_id` | conversa e `ConversationScope` |

- `account_id` é o envelope que o `broadcast` nativo já põe em todo payload (`action_cable_listener.rb:358`). Está na lista por isso; é o único campo além do pedido.
- **Não chegam ao admin:** `previous_changes` (message.updated), `event_metadata`, `performer` (só o broadcast nativo acrescenta), mensagens, conteúdo, anexos, contato (`contact_inbox`, `meta`, `sender`), labels e `messages`.
- **Admin não recebe:** `conversation.mentioned`, `conversation.unread_count_changed`, eventos de mensagem agendada e recorrente (fora de Q-10). Decisão de leitura, a confirmar.

### 7.3 Resultados

Todas pelo runner com o lock compartilhado (`flock -w 900 .../spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply <specs>`).

| Run | Specs | Exemplos | Falhas | Exit | Log |
|---|---|---|---|---|---|
| c2a-1 | `scope_socket_spec.rb` (primeira execução) | 21 | 0 | 0 | `09-logs/run-c2a-1-socket.log` |
| c2a-2 | `scope_policy_query_spec.rb` + `scope_http_filter_spec.rb` | 64 | 0 | 0 | `09-logs/run-c2a-2-regressao.log` |
| c2a-3 | `scope_socket_spec.rb` (final, após ajuste de RuboCop) | 21 | 0 | 0 | `09-logs/run-c2a-3-socket-final.log` |

RuboCop (`env -i` com PATH do toolchain e `BUNDLE_GEMFILE`, `BUNDLE_PATH`, `BUNDLE_FROZEN` do launcher) em `socket_hook.rb`, `admin_metadata_broadcast_job.rb` e `scope_socket_spec.rb`: 3 arquivos, sem ofensas, exit 0. Log: `09-logs/rubocop-09-c2a.log`. Antes do ajuste final houve 1 ofensa (`RSpec/ContainExactly`, `scope_socket_spec.rb:77`), corrigida no próprio spec.

Exemplos novos ou alterados em `spec/connecta/scope_socket_spec.rb` (todos asserção sobre o payload enfileirado; o job não é executado):
- admin nominal e nativo recebem só `{id, conversation_id, account_id}` em `message.created` (exato, sem chaves de conteúdo);
- agente com grant recebe o payload completo (`:content`, `:conversation`);
- payload com conteúdo chega exatamente a agente e gestor com grant;
- conversa sem escopo: só admins, só metadados;
- `message.updated` sem `previous_changes` para admin; `conversation.updated` e `assignee.changed` com exatamente `{id, inbox_id, status, org_unit_id, account_id}`;
- `conversation.mentioned`: agente com grant recebe; agente de outro setor, membro sem grant e admin não recebem; controle em inbox não marcada segue nativo;
- `conversation.unread_count_changed` (feature `conversation_unread_counts` ligada no exemplo): só agente com grant e gestor; controle em inbox não marcada com membro e admin nativo.

Os 12 exemplos anteriores foram atualizados onde o admin passou a ter metadado (ex.: `chega exatamente a quem o Gate lê` agora separa conteúdo de metadado). Total: 21.

**Não feito:** teste de mutação (remover o filtro e ver os exemplos falharem). A prova é por leitura do código e pela asserção do payload enfileirado.

### 7.4 Pendências e riscos

- **Job nativo.** `ActionCableBroadcastJob#prepare_broadcast_data` (`app/jobs/action_cable_broadcast_job.rb:26`) substitui o payload por `conversation.push_event_data`. Um payload reduzido não pode passar por ele. O spike resolve com job próprio. Produção precisa de decisão: (A) job próprio, como aqui; ou (B) alterar o job nativo para não recarregar quando o payload vier marcado (mexe em core, fora do escopo).
- **Conversa apagada em inbox marcada** não tem exemplo de spec (o ramo existe em `socket_hook.rb:45-50`).
- **Custo.** Por evento de inbox marcada: uma consulta de admins (nativos + nominais com `Projection#admin?`) e uma de `ConversationScope`. Não medido.
- **Leitura de "admin":** adotei nativo (`administrator`) e nominal (grant `admin_nominal` verificado). Se o pedido quis só o nominal, ajustar `socket_admin_tokens`.
- **Não verificado:** frontend. Nenhum cliente foi testado com o payload reduzido (ex.: se algum componente espera `messages` ou `meta` em evento de conversa e quebra com o campo ausente).

### 7.5 Sugestão de registro (gotchas.md, fora da ownership desta tarefa)

- 2026-10-23 — `ActionCableBroadcastJob` relê a conversa em `conversation.read/updated`, `team.changed`, `assignee.changed` e `conversation.status_changed`: um payload reduzido enviado por esse job volta completo. Metadados de admin usam `Connecta::Scope::AdminMetadataBroadcastJob` — evidência: `app/jobs/action_cable_broadcast_job.rb:26`, `app/services/connecta/scope/socket_hook.rb:69-75`.
- 2026-10-23 — `conversation.mentioned` vai direto ao token do mencionado (sem `user_tokens`): o filtro precisa estar no próprio método do listener — evidência: `app/listeners/action_cable_listener.rb:290-295`, `socket_hook.rb:36-41`.

## 8. T0.2-c2b (2026-10-23): digitação, contatos e presença

**Estado: c2b fechado com um ponto aberto.** Digitação (AC1) e contato vinculado (AC2, exceto exclusão) estão provados por spec. Presença (AC3) está caracterizada. `contact.deleted` tem ramo de código, mas sem exemplo e com janela de corrida (§8.4, item 1). Código alterado: `socket_hook.rb` e `scope_socket_spec.rb` (diretórios não rastreados). `git diff` de arquivos rastreados segue vazio.

### 8.1 Código

- `socket_hook.rb:14`: `conversation_typing_on`, `conversation_typing_off` e `conversation_recording` entram em `CONVERSATION_EVENTS`. A conversa fica gravada e `user_tokens` (`:61`) filtra pelo Gate; admins ficam de fora. Antes, sem chave de conversa, `action_cable_listener.rb:314-318` enviava a membros e admins nativos.
- `socket_hook.rb:31`: `CONTACT_EVENTS` (created, updated, merged, deleted, group_synced; `action_cable_listener.rb:255-288`).
- `socket_hook.rb:77-78` (`broadcast`): evento de contato com `ContactInbox` em inbox marcada (`socket_contact_linked?`, `:101-103`) troca o stream `account_<id>` pelos tokens de `contact_reader_tokens` (`:106-111`).
- `socket_hook.rb:114-118` (`socket_contact_reader?`): admin nominal sai antes da consulta; os demais passam por `ContactVisibility.visible_scope(account, user).exists?(contact_id)`.
- Candidatos: membros das inboxes marcadas do contato (`InboxMember`), o mesmo critério das mensagens (`user_tokens` de `socket_hook.rb`, `action_cable_listener.rb:77`).
- `installer.rb` sem alteração: `SocketHook` já é prepended em `ActionCableListener` (`installer.rb:50`). `ContactVisibility` lido, não alterado (fora do IN-SCOPE).

### 8.2 Eventos: destinatários antes → agora (inbox marcada)

| Evento | Origem (listener) | Antes | Agora |
|---|---|---|---|
| `conversation.typing_on` / `typing_off` / `recording` | `action_cable_listener.rb:186-232`; tokens `:303-312` | membros e admins nativos, mais o token do contato | agentes com grant e gestor (Gate); token do contato mantido (§8.4, item 4); admins fora |
| `contact.created` / `updated` / `merged` / `group_synced` | `action_cable_listener.rb:255-288`; `account_token` `:299-301` | stream `account_<id>`, que todo User assina (`room_channel.rb:27-30`) | quem `ContactVisibility` permite e é membro da inbox; stream da conta não recebe |
| `contact.deleted` | `action_cable_listener.rb:270-276` | stream da conta | mesmo ramo, sem exemplo (§8.4, item 1) |
| contato sem vínculo (qualquer `contact.*`) | idem | stream da conta | stream da conta (controle) |

### 8.3 Resultados

Todas pelo runner com o lock compartilhado (`flock -w 900 .../spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply <specs>`).

| Run | Specs | Exemplos | Falhas | Exit | Log |
|---|---|---|---|---|---|
| c2b-1 | `scope_socket_spec.rb` | 30 | 0 | 0 | `09-logs/run-c2b-1-socket.log` |
| c2b-2 (mutação: typing e contato vinculado desligados; arquivo restaurado e conferido com `cmp`) | `scope_socket_spec.rb` | 30 | 7 | 1 | `09-logs/run-c2b-2-mutacao-sem-typing-e-contato.log` |
| c2b-3 | `scope_related_http_spec.rb` | 64 | 0 | 0 | `09-logs/run-c2b-3-related-http.log` |

- Exemplos: 21 → 30 (+9: 4 de digitação, 5 de contato).
- Mutação: falharam as 7 esperadas (3 de digitação e 4 de contato vinculado). Os dois controles (digitação em inbox não marcada e contato sem vínculo) passaram, o que mostra que o filtro é específico.
- RuboCop em `socket_hook.rb` e `scope_socket_spec.rb`: 2 arquivos, sem ofensas, exit 0 (`09-logs/rubocop-09-c2b.log`).
- `git diff --check`: sem saída, exit 0. `git status --short`: nenhuma entrada rastreada alterada.

### 8.4 Pontos abertos e decisões

1. **`contact.deleted` (AC2 incompleto).** O listener roda síncrono depois do commit (`sync_dispatcher.rb:8`, `contact.rb:74`). A checagem de vínculo lê `contact_inboxes`, mas essa associação usa `destroy_async` (`contact.rb:62`). Se o job já removeu os vínculos quando o listener roda, o evento cai no stream da conta, com nome, telefone e e-mail do contato apagado (`contact.rb:257-263`). Se os vínculos ainda existem, ninguém recebe, porque `visible_scope` não acha o contato apagado; quem podia ver segue com o contato na lista até recarregar. Não há exemplo: um destroy real depende de job e não reproduz esse estado. Fechar de vez exige capturar o vínculo antes do destroy (hook em `contact.rb`, core, fora do escopo) ou aceitar a janela. **Decisão pendente.**
2. **`contact.created` (não verificado).** `dispatch_create_event` roda em `after_create_commit` (`contact.rb:72`). Se o `ContactInbox` for criado depois do commit do contato, o evento sai no stream da conta. Não olhei o fluxo de criação do Baileys; não há exemplo para esse caso.
3. **Candidatos são membros da inbox.** Quem tem grant no setor mas não é membro da inbox não recebe contato em tempo real. É o critério das mensagens, então o caso fica fail-closed. Decisão: manter, ou usar todos os usuários com grant como candidatos.
4. **Token do contato em digitação.** O cliente (`ContactInbox`) continua recebendo o typing do agente, como no nativo (`action_cable_listener.rb:310`). Ele é a outra parte da conversa, não usuário interno, e o Gate não se aplica. Se o pedido for "só usuários internos", o token sai de `typing_event_listener_tokens`.
5. **Extras além da lista do briefing.** `conversation.recording` (mesmo caminho de typing, `action_cable_listener.rb:202-216`) e `contact.group_synced` (dentro da faixa `257-287`; payload com membros do grupo, `:278-288`).
6. **Admin nominal e auditoria.** `ContactVisibility.visible_scope` para admin nominal grava `AccessAudit` `list` (`conversation_query.rb`, `admin_listing`). Por isso admin sai antes da consulta (`socket_hook.rb:114-118`). Sem isso, cada contato vinculado geraria um registro de listagem por admin.
7. **Custo.** Por evento de contato vinculado: uma consulta de vínculo, uma de membros e um `exists?` por membro não admin. Não medido.

### 8.5 Presença (AC3, caracterizada, sem alteração)

- Origem: `app/channels/room_channel.rb:19-25` (`broadcast_presence`). O briefing cita `action_cable_listener.rb:19-25`, mas lá está `notification_deleted`. A presença não passa pelo listener.
- Destino: `pubsub_token` do próprio assinante (`room_channel.rb:24`). Não passa por `socket_hook`.
- Conteúdo: `account_id`; `users` = `{user_id: disponibilidade}` dos usuários online da conta (`room_channel.rb:22`); `contacts` = `{contact_id: 'online'}`, só para assinante `User` (`room_channel.rb:23`).
- Carrega dado de conversa? **Não.** Sem mensagem, conversa, nome ou e-mail. Mas a lista de ids e disponibilidade de usuários da conta vai a qualquer assinante, sem Gate. E os ids de contatos online podem incluir contatos vinculados a inbox marcada: é sinal de atividade, não conteúdo. Decisão para produção: filtrar `contacts` por `ContactVisibility`?
- Sem spec para presença.

### 8.6 Cobertura do socket: evento → coberto por → exemplo

| Evento | Coberto por (código) | Exemplo em `scope_socket_spec.rb` |
|---|---|---|
| `message.created` | `socket_hook.rb` `CONVERSATION_EVENTS` + `user_tokens` | 'agente com grant recebe a mensagem'; 'payload com conteúdo chega exatamente a quem o Gate lê'; 'admin nominal e nativo recebem só id…' |
| `message.updated` | idem | 'message.updated segue o mesmo filtro…' |
| `first_reply.created` | idem | sem exemplo |
| `conversation.created` / `read` / `status_changed` / `team.changed` / `contact_changed` | idem | sem exemplo |
| `conversation.updated` | idem | 'conversation.updated segue o mesmo filtro…' |
| `assignee.changed` | idem + `broadcast` (metadados de admin) | 'assignee.changed … entrega ao admin só metadados' |
| `scheduled_message.*` / `recurring_scheduled_message.*` | idem | sem exemplo |
| `conversation.typing_on` | `CONVERSATION_EVENTS` (c2b) | 'digitação do cliente chega só a agente com grant e gestor' |
| `conversation.typing_off` | idem | 'fim de digitação segue o mesmo filtro' |
| `conversation.recording` | idem | 'gravação de áudio segue o mesmo filtro' |
| digitação em inbox não marcada | nativo | 'controle: digitação em inbox não marcada…' |
| `contact.updated` (vinculado) | `CONTACT_EVENTS` + `broadcast` (c2b) | 'atualização vai só a quem o ContactVisibility permite…' |
| `contact.created` (vinculado) | idem | 'criação segue a mesma regra' |
| `contact.merged` (vinculado) | idem | 'fusão segue a mesma regra' |
| `contact.group_synced` (vinculado) | idem | 'agrupamento de grupo segue a mesma regra' |
| `contact.deleted` (vinculado) | idem, ramo não testado (§8.4, item 1) | sem exemplo |
| contato sem vínculo (`contact.*`) | nativo | 'controle: contato sem vínculo…' |
| `conversation.mentioned` | método próprio (c2a) | 4 exemplos (c2a) |
| `conversation.unread_count_changed` | método próprio (c2a) | 2 exemplos (c2a) |
| `presence.update` | `room_channel.rb:19-25`, fora do listener | sem exemplo (§8.5) |
| `notification.*` | fora (c5) | — |
| `account.cache_invalidated`, `inbox.provider_connection_updated` | fora desta tarefa | — |

### 8.7 Não verificado

- Fluxo real de criação de contato Baileys (§8.4, item 2).
- Corrida do `destroy_async` na exclusão (§8.4, item 1): não reproduzida.
- Frontend: quem deixa de ver um contato não tem atualização da lista até recarregar; não testado.

### 8.8 Sugestão de registro (gotchas.md, fora da ownership desta tarefa)

- 2026-10-23 — `ContactVisibility.visible_scope` grava `AccessAudit` `list` para admin nominal a cada chamada (`conversation_query.rb`, `admin_listing`); por isso o socket exclui admin antes da consulta — evidência: `app/services/connecta/scope/socket_hook.rb:114-118`
- 2026-10-23 — `contact.deleted` é despachado de forma síncrona após o commit, com `contact_inboxes` em `destroy_async`: o vínculo pode já ter sumido quando o listener lê — evidência: `app/models/contact.rb:62,74`, `app/dispatchers/sync_dispatcher.rb:8`
- 2026-10-23 — o listener envia contato a `[account_token(account)]` fixo; trocar o destino exige mexer em `broadcast`, não em cada método — evidência: `app/listeners/action_cable_listener.rb:257-287,299-301`
