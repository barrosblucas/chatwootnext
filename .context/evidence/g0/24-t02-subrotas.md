# 24 — T0.2 leftovers: 11 sub-rotas B1 + bulk collection (IMPLEMENTADO / NÃO EXECUTADO)

- Data (UTC): 2026-10-24.
- TASK_ID: g0-t02-c9.
- Natureza: **escrita de spec + registro documental**. Nenhum código de app/installer/support/schema foi alterado **nesta tarefa documental**; nenhum spec foi executado; nenhum lint/build foi executado.
- Status: **IMPLEMENTADO (spec escrito) / NÃO EXECUTADO (funcional)** — inclui as 2 correções de código de outra frente só como leitura/ponteiro, sem declarar teste verde.
- Arquivo de spec: `spec/connecta/scope_b1_leftovers_spec.rb` (41 exemplos escritos contados por `grep -cE "^[[:space:]]*it[[:space:]]+'"` , NÃO EXECUTADOS).
- Base de leitura (rotas reais e before_actions reais; outros specs em mutação por outras frentes — Captain, anexos, team, socket — **não** foram lidos):
  - `config/routes.rb:155-193` (rotas reais das 11 superfícies sob `conversations/:id` e `conversations/:conversation_id/...`)
  - `app/controllers/api/v1/accounts/conversations_controller.rb` (mute/unmute/transcript/toggle_status/toggle_priority/toggle_typing_status/presence_subscribe/update_last_seen/unread/custom_attributes)
  - `app/controllers/api/v1/accounts/conversations/base_controller.rb` (`before_action :conversation` + `authorize :show?`)
  - `app/controllers/api/v1/accounts/conversations/scheduled_messages_controller.rb` (index/create/update/destroy + policies/params)
  - `app/controllers/api/v1/accounts/conversations/recurring_scheduled_messages_controller.rb` (index/create/update/destroy + params)
  - `app/controllers/api/v1/accounts/conversations/messages/reactions_controller.rb` (create sob `messages/:message_id`; canal baileys suporta reações)
  - `app/controllers/api/v1/accounts/conversations/direct_uploads_controller.rb` (HISTÓRICO §2: herda `ActiveStorage::DirectUploadsController`, NÃO herda `Conversations::BaseController`; na escrita original o hook de escopo NÃO estava instalado — achado preservado; correção test-only em outra frente, ver ponteiros abaixo, sem teste verde)
  - `app/services/connecta/scope/direct_uploads_hook.rb:1-25` (CORREÇÃO test-only, só leitura: `create` com `connecta_scope_direct_upload_guard!` após autenticação nativa; resolve `display_id` em `Current.account`; inbox marcada exige leitura 404 + escrita 403 via `Gate`/`Denied`; inbox não marcada segue nativo)
  - `app/services/connecta/scope/presence_bulk_hook.rb:1-28` (CORREÇÃO test-only, só leitura: `connecta_scope_presence_bulk_guard!`; resolve `conversation_ids` (limite 10) em `Current.account`; alvos marcados exigem as MESMAS leitura 404 + escrita 403 da presença unitária; lote misto nega antes de qualquer `PresenceSubscribeService`/provedor; só unmarked segue nativo)
  - `app/services/connecta/scope/installer.rb:30-43,104-113` (instalação TEST-ONLY, só leitura: `install!` com guard `Rails.env.test?`; `DirectUploadsController.prepend(DirectUploadsHook)` + `Denied` rendering; `ConversationsController.prepend(PresenceBulkHook)` + `before_action :connecta_scope_presence_bulk_guard!, only: :presence_subscribe_bulk`)
  - `app/services/connecta/scope/conversation_http_hook.rb` (proteção central vigente, leitura 404 / escrita 403)
  - `app/services/connecta/scope/gate.rb`, `projection.rb`, `policy_hook.rb`, `denied.rb` (contrato de leitura/escrita)
  - `spec/connecta/scope_http_filter_spec.rb`, `spec/connecta/scope_related_http_spec.rb`, `spec/connecta/scope_b2_complements_spec.rb` (cobertura já existente, para não repetir casos)
  - `spec/connecta/support/g0_scope_fixture.rb` (fixture reutilizada sem edição: dois setores, gestor, membro sem grant, admin nominal, inbox controle)
- Checagem de espaço (somente leitura, sem apagar): `df -h /tmp` → `tmpfs 7.6G, 5.1G usados, 2.6G livres, 67%` em 2026-10-24.

## 1. Tabela rota/ação/caso/status (rotas concretas verificadas em `config/routes.rb`)

| # | Superfície (briefing) | Rota real identificada | Casos no spec novo | Status |
|---|---|---|---|---|
| 1 | scheduled_messages | `GET/PATCH/DELETE /api/v1/accounts/:account_id/conversations/:conversation_id/scheduled_messages[/:id]` (create negado já coberto na B1, não repetido) | outro setor + membro 404 sem vazar conteúdo; gestor lê 200 mas PATCH/DELETE 403 sem alterar; agente atualiza + apaga | IMPLEMENTADO NÃO EXECUTADO |
| 2 | recurring (`recurring_scheduled_messages`) | `GET/DELETE /api/v1/accounts/:account_id/conversations/:conversation_id/recurring_scheduled_messages[/:id]` + `PATCH` (update existe na rota; destroy cancela via `status: cancelled` + mensagem de atividade) (create negado já coberto na B2, não repetido) | outro setor + membro 404; gestor PATCH 403 sem alterar; agente lista 200 + cancela; controle lista 200 | IMPLEMENTADO NÃO EXECUTADO |
| 3 | reactions | `POST /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:message_id/reactions` (canal baileys em `REACTION_SUPPORTED_PROVIDERS`, `channel/whatsapp.rb:37`) | outro setor + membro 404 sem criar mensagem; gestor 403 sem criar e sem `SendReplyJob`; agente reage em nota privada (sem saída ao provedor, stub `send_message`); controle sem suporte responde 422 nativo | IMPLEMENTADO NÃO EXECUTADO |
| 4 | direct_uploads | `POST /api/v1/accounts/:account_id/conversations/:conversation_id/direct_uploads` — **HISTÓRICO (§2): na escrita original o controller herdava `ActiveStorage::DirectUploadsController` sem hook de escopo; CORREÇÃO test-only vigente em `app/services/connecta/scope/direct_uploads_hook.rb:1-25` + `installer.rb:38,111`** | outro setor + membro 404 sem criar blob nem emitir URL; gestor 403 sem criar blob; agente cria blob; controle de inbox não marcada cria nativamente | IMPLEMENTADO NÃO EXECUTADO |
| 5 | custom_attributes | `POST /api/v1/accounts/:account_id/conversations/:id/custom_attributes` (positivo do agente já coberto na B2, não repetido) | outro setor + membro 404 sem mudar valor; controle atualiza 200 nativo | IMPLEMENTADO NÃO EXECUTADO |
| 6 | mute | `POST /api/v1/accounts/:account_id/conversations/:id/mute` (`mute!` resolve + bloqueia contato) | outro setor + membro 404 sem resolver/silenciar e sem mensagem; gestor 403 sem alterar; agente silencia (resolved + muted) | IMPLEMENTADO NÃO EXECUTADO |
| 7 | unmute | `POST /api/v1/accounts/:account_id/conversations/:id/unmute` (superfície própria; briefing lista mute e unmute juntos mas a rota de `unmute` é distinta — contada aqui como caso próprio, não como 12ª superfície) | outro setor + membro 404 segue silenciada; gestor 403 sem alterar; agente remove silêncio | IMPLEMENTADO NÃO EXECUTADO |
| 8 | presence_subscribe | `POST /api/v1/accounts/:account_id/conversations/:id/presence_subscribe` (member; `PresenceSubscribeService`; bulk collection coberta na linha 12 com guarda própria test-only) | outro setor + membro 404 sem I/O (`a_request` nada feito); gestor 403 sem `PresenceSubscribeService.new`; agente 200 sem I/O; controle 200 nativo | IMPLEMENTADO NÃO EXECUTADO |
| 9 | update_last_seen | `POST /api/v1/accounts/:account_id/conversations/:id/update_last_seen` (member; throttle nativo 1h, mas com mensagem não lida atualiza sempre) | outro setor + membro 404 sem tocar `agent_last_seen_at`; gestor 403 sem tocar; agente atualiza com incoming não lida | IMPLEMENTADO NÃO EXECUTADO |
| 10 | toggle_typing_status | `POST /api/v1/accounts/:account_id/conversations/:id/toggle_typing_status` (member; `TypingStatusManager` despacha via dispatcher) | outro setor + membro 404 sem dispatch; gestor 403 sem dispatch; agente 200 com dispatch; controle 200 nativo | IMPLEMENTADO NÃO EXECUTADO |
| 11 | unread | `POST /api/v1/accounts/:account_id/conversations/:id/unread` (member; despacha `CONVERSATION_UNREAD` e reloga `agent_last_seen_at`) | outro setor + membro 404 sem dispatch e sem relogar; gestor 403 sem dispatch e sem relogar; agente 200 | IMPLEMENTADO NÃO EXECUTADO |
| 12 | presence_subscribe_bulk | `POST /api/v1/accounts/:account_id/conversations/presence_subscribe_bulk` (collection, sem `:id`; **CORREÇÃO test-only vigente em `app/services/connecta/scope/presence_bulk_hook.rb:1-28` + `installer.rb:41-42`** — guarda própria com mesmas leitura 404 + escrita 403 da presença unitária) | outro setor + membro 404 sem serviço/provedor; gestor 403 sem serviço; misto permitido+proibido nega 404 antes de efeitos; agente autorizado 200 sem I/O externo; controle unmarked 200 nativo | IMPLEMENTADO NÃO EXECUTADO |

Nota de contagem (AC1): o briefing lista 10 nomes e 11 superfícies member; `mute`/`unmute` são duas rotas member distintas (`routes.rb:179-180`) e foram tratadas como superfícies 6 e 7; `presence_subscribe_bulk` é collection (fora do guard de conversa) e entra como linha 12 com guarda própria test-only. Contagem real do spec: **41 exemplos** (`grep -cE "^[[:space:]]*it[[:space:]]+'" spec/connecta/scope_b1_leftovers_spec.rb` → 41; 12 blocos `describe`, 1 `RSpec.describe` raiz). Nenhuma superfície ficou sem caso individual e nenhuma rota foi inventada: todos os caminhos acima existem em `routes.rb:155-193`.

## 2. HISTÓRICO + CORREÇÃO: `direct_uploads` e `presence_subscribe_bulk` (código corrigido em outra frente, spec NÃO EXECUTADO)

### 2.1 Achado histórico preservado (escrita original do spec)
- Na escrita original, `direct_uploads_controller.rb:1` herdava `ActiveStorage::DirectUploadsController`, não `Conversations::BaseController`; o `Installer.install_conversations!` da época só fazia prepend/hook em `ConversationsController` e `Conversations::BaseController` — logo `connecta_scope_write_guard!` **não** rodava nesta rota.
- Na época, o controller validava conta/token (`current_account`, `authenticate_user!`/token) mas não chamava `authorize @conversation, :show?` nem o Gate; o spec original documentava o comportamento nativo (membro sem grant criaria blob com 200) como ACHADO explícito, sem alegar negação de ACL.
- Da mesma forma, `presence_subscribe_bulk` (collection, sem `:id`) não passava pelo guard de conversa e constava como NÃO coberto.

### 2.2 Correções vigentes (outra frente, só leitura aqui — sem teste verde)
- `direct_uploads_hook.rb:1-25`: `create` com `connecta_scope_direct_upload_guard!` após autenticação nativa e carregamento da conta, antes de criar o blob (sem `signed_id`/URL antes de autorizar). Conversa resolvida sempre em `Current.account` (IDs de outra conta → 404). Inbox marcada: leitura negada → 404, escrita negada → 403 (contrato `Gate`/`Denied`/auditoria). Inbox não marcada: segue nativo.
- `presence_bulk_hook.rb:1-28`: `connecta_scope_presence_bulk_guard!` resolve `conversation_ids` (limite 10) em `Current.account`, sem consulta global. Todo alvo marcado exige as MESMAS leitura 404 + escrita 403 da presença unitária (`access_path: 'conversation_presence_subscribe_bulk'`); lote misto com alvo marcado não autorizado nega antes de qualquer `PresenceSubscribeService`/provedor (sem efeito parcial). Só unmarked segue nativo; autorizado marcado segue serviço nativo.
- Instalação TEST-ONLY em `installer.rb:30-43,104-113`: `install!` com guard `Rails.env.test?` (fora de specs G0 os hooks não são prepended e o nativo permanece); `DirectUploadsController.prepend(DirectUploadsHook)` + rendering `Denied`; `ConversationsController.prepend(PresenceBulkHook)` + `before_action :connecta_scope_presence_bulk_guard!, only: :presence_subscribe_bulk`.
- Cobertura escrita atual (NÃO EXECUTADA): `direct_uploads` com 3 exemplos (outro setor+membro 404 sem blob/URL; gestor 403 sem blob; agente cria + controle nativo cria) em `scope_b1_leftovers_spec.rb:170-200`; `presence_subscribe_bulk` com 5 exemplos (outro setor+membro 404 sem serviço/provedor; gestor 403 sem serviço; misto nega 404 antes de efeitos; agente 200 sem I/O; controle 200 nativo) em `scope_b1_leftovers_spec.rb:317-365`.

## 3. Diferenciação 404 de ACL × 404 de rota/fixture (AC2)

- Todas as negações de leitura usam conversa `conv_a` do fixture (display_id real, inbox marcada, escopo `active`, `case_version: 1`) — portanto 404 só pode vir do `PolicyHook`/`conversation` rescue (leitura negada), nunca de rota inexistente ou fixture ausente.
- Positivos usam o mesmo `conv_a` com `agent_a` (grant `atender` no setor A) — caminho real passa por `conversation` → `show?` → Gate → controller nativo.
- Controles usam `conv_control` (inbox NÃO marcada, `agent_a` membro) — preservam comportamento nativo (200/422 conforme a rota).
- 401 (não autenticado) **não** foi repetido aqui: já coberto na B1 (`scope_http_filter_spec.rb` § autenticação) para lista/detalhe/mensagens/filtro/envio/criação.

## 4. Ausência de efeitos/enqueue em negação (por superfície)

- scheduled: `not_to change(ScheduledMessage, :count)` no DELETE do gestor; conteúdo intacto após PATCH negado.
- recurring: conteúdo intacto após PATCH negado do gestor.
- reactions: `not_to change(Message, :count)` (outro setor/membro/gestor) + `not_to have_enqueued_job(SendReplyJob)` (gestor).
- custom_attributes: valor intacto após 404 de outro setor/membro.
- mute/unmute: `status`/`muted?` intactos + `not_to change(Message, :count)` (mensagens de atividade de mute) nas negações.
- presence_subscribe: `expect(Conversations::PresenceSubscribeService).not_to receive(:new)` (gestor) + `a_request(:any, /.*/)` nada feito (todos, sem transporte real/LLM/rede).
- presence_subscribe_bulk: `expect(Conversations::PresenceSubscribeService).not_to receive(:new)` (outro setor/membro, gestor, misto) + `a_request(:any, /.*/)` nada feito (stub `stub_request(:any, /.*/)` só no bloco bulk; negações sem serviço/provedor; misto nega antes de efeitos).
- direct_uploads: `not_to change(ActiveStorage::Blob, :count)` (outro setor/membro 404, gestor 403) + `to change(ActiveStorage::Blob, :count).by(1)` nos positivos (agente marcado e controle unmarked nativo).
- toggle_typing_status/unread: dispatcher stubado com `allow(...).to receive(:dispatch)` e `not_to have_received(:dispatch)` nas negações; `agent_last_seen_at` inalterado no `unread` negado.
- update_last_seen: `not_to change { conv_a.reload.agent_last_seen_at }` nas negações.

## 5. Limites (o que este spec NÃO prova)

- Spec **escrito e NÃO executado**: 41 exemplos contados por `grep -cE` (sem executar); `rspec` proibido pelo briefing e não rodado; nenhum teste verde é alegado.
- Código das 2 correções lido, não executado: sintaxe `3.4.4` citada em logs de outra frente (`/home/thanos/.local/state/opencode-coder/20261024T170747-884873` e `.../20261024T171316-904021`, em mutação — não lidos aqui); instalação test-only (`Rails.env.test?`) não verificada em runtime nesta tarefa.
- Stub mínimo de transporte externo: `WhatsappBaileysService#send_message` stubado (reações), dispatcher de digitação stubado e `stub_request(:any, /.*/)` no bloco bulk — sem rede/LLM/transporte real.
- `direct_uploads`/`presence_subscribe_bulk`: correções existem em código test-only (§2.2), mas a cobertura escrita (3 + 5 exemplos) segue NÃO EXECUTADA — sem prova funcional.
- Casos já cobertos em B1/B2 (create de scheduled, create de recurring, positivo de custom_attributes, update/destroy de scheduled do gestor na B1 § rascunho, 401) não foram repetidos sem necessidade.
- Nenhum teste verde é alegado: todo status acima é IMPLEMENTADO NÃO EXECUTADO.
