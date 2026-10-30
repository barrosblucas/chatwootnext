# T0.2-c7b · complemento Captain/Copilot (G0, 2026-10-23/24)

**Estado: NÃO VALIDADO.** Código escrito, sem specs executadas (por instrução do humano). Validação funcional
pendente em tarefa posterior. `git diff --check` limpo; `git status --short` só com `??` (nada rastreado alterado).

Escopo: completar APENAS o código interrompido da proteção Copilot/Captain (T0.2-c7b). Arquivos próprios:
`app/services/connecta/scope/{copilot_hook,copilot_chat_hook,copilot_tool_hook,captain_http_hook,inbox_hook,installer}.rb`.
Nenhum spec foi escrito ou executado aqui. `spec/connecta/captain_scope_spec.rb:164-190` segue intocado (ainda
caracteriza o vazamento; a correção será provada na tarefa de specs).

## 1. AC1 — Copilot nega IDs fora do escopo antes de persistir, enfileirar ou consultar conteúdo

- `copilot_hook.rb` (`connecta_scope_copilot_guard!`): ligado como `prepend_before_action(..., only: :create)` nos
  dois controllers (`installer.rb`), roda antes de `CopilotThread(s).create!` e de `enqueue_response_job`.
  `conversation_id` em branco segue nativo; não autenticado (`current_user.nil?`) segue para o 401 nativo sem negar
  (decisão 002). ID inexistente na conta vira 404 sem revelar outra conta (`find_by` escopado por `Current.account`).
  Conversa de inbox não marcada segue nativa (sem Gate). Conversa de inbox marcada: só com `Gate#read?`; negado vira
  404 (`Denied, :not_found`) com auditoria `copilot_conversation` (allow/deny pelo Gate).
- `copilot_chat_hook.rb` (`current_viewing_history` + `connecta_scope_copilot_denied?`): segunda barreira no
  `ChatService`. Se o job for enfileirado por outro caminho, o contexto do modelo recebe `[]` (sem ID de conversa
  nem de contato) quando o Gate nega em inbox marcada. Inbox não marcada segue nativa.
- `copilot_tool_hook.rb` (`execute` + guards): `GetConversationService#execute` só passa quando a conversa está no
  `ConversationQuery` do próprio `@user` (fail-closed sem usuário); negado devolve `'Conversation not found'` sem
  ID, contato ou conteúdo. `GetContactService`/`SearchContactsService#execute` só passam quando o contato está no
  `ContactVisibility` do próprio `@user`; negado devolve `'Contact not found'`. `SearchConversationsService` já passa
  pelo `FinderHook` via `PermissionFilterService` (instalado no spike), por isso não recebe guard próprio. Controles
  não marcados preservados: `ConversationQuery`/`ContactVisibility` devolvem a relação nativa fora da inbox marcada.
- Link entre camadas: o create HTTP barra antes de persistir/enfileirar; o ChatService barra o contexto do modelo;
  as ferramentas barram o lookup direto. Links/IDs de outra conta não dão acesso (lookup sempre escopado pela conta).

## 2. AC2 — hooks realmente instalados; instalação reexecutável; controles não marcados preservados

`installer.rb` (`install_inboxes_and_captain!` + `install_denied_rendering!`):

- `CopilotThreadsController` + `CopilotHook` (prepend) + `prepend_before_action(:connecta_scope_copilot_guard!)`.
- `CopilotMessagesController` + `CopilotHook` (prepend) + `prepend_before_action(:connecta_scope_copilot_guard!)`.
- `AgentSessionsController` + `CaptainHttpHook` (prepend, sobrescreve `authorize_conversation`).
- `MessageReportsController` + `CaptainHttpHook` (prepend, sobrescreve `authorize_conversation`).
- `Captain::Copilot::ChatService` + `CopilotChatHook` (prepend).
- `GetConversationService`, `GetContactService`, `SearchContactsService` + `CopilotToolHook` (prepend no `execute`).
- `rescue_from(Denied)` nos 4 controllers Captain acima (404 de leitura).
- Instalação segue reexecutável no padrão do spike (só `Rails.env.test?`; prepend idempotente por chamada única do
  `Installer.install!` nos specs). Controles não marcados: nenhum guard nega fora de `Projection.marked?`; o
  comportamento nativo vale (show/campanhas da inbox, threads próprias, ferramentas em inbox não marcada).

## 3. AC3 — Captain marcado sem acesso dá 404; inbox_update audita só allow autorizado de fato

- `captain_http_hook.rb` (`authorize_conversation`, sobrescrito em vez de guard em `before_action` separado): o Gate
  roda antes do `authorize` nativo em inbox marcada; sem leitura autorizada, 404 (`Denied, :not_found`) com auditoria
  `captain_show`/`captain_create` (allow/deny pelo Gate). Sem passar pelo 401 do Pundit (sem mudar o `rescue` global).
  Inbox não marcada segue nativa; não autenticado segue 401 (guard retorna sem negar).
- `inbox_hook.rb`: `fetch_inbox` só agenda auditoria nominal pendente para ações em `NOMINAL_ACTIONS` em inbox
  marcada (sem gravar allow antes da autorização nativa). `check_authorization` sobrescrito: `super` primeiro
  (nativo decide o 401); só com `super` sem exceção o pendente vira `allow` (`inbox_<ação>`, `surface: inbox`,
  sem duplicar trilha — `take_pending_audit!` consome a entrada). Com `Pundit::NotAuthorizedError`, o pendente é
  descartado e o 401 nativo segue (sem allow fantasma — fecha o ACHADO-1 da evidência 15). `update` com papel de
  agente na inbox marcada: 401 nativo, nome intacto, nenhum `allow` em `inbox_update`.
- `connecta_scope_inbox_create_guard!` (só `channel.type == 'whatsapp'`): fora disso, segue nativo. Com WhatsApp:
  nega não-admin antes de qualquer I/O (`deny` em `inbox_create` + 403); só quando o admin nominal também é
  `administrator` da conta o `allow` em `inbox_create` é gravado. Sem `allow` antes da negação nativa.
- `connecta_scope_nominal_guard!` mantido para os caminhos imediatos (não diferidos); `show`/campanhas e `GET`
  seguem nativos sem auditoria de inbox (caracterização da evidência 15, sem mudança).

## 4. AC4 — arquivos próprios; validação funcional explicitamente pendente

- Escrita exclusiva respeitada: só os 6 arquivos de `app/services/connecta/scope/` acima. Nenhum helper novo em
  `scope/**` foi necessário. `transfer/**`, `runner`, `schema`, anexos, `team_id`, contato, sub-rotas, core, `.env`,
  SQL, banco, migração, teardown, `/tmp`, servidor, QR, commit: intocados. Plano e `PROJECT_STATE` intocados.
- `transfer/` e specs de outro Coder: não lidos em mutação, não revertidos.
- Validação nesta tarefa: `git diff --check` (limpo) e `git status --short` (só `??`). **NENHUM SPEC, RUBOCOP OU
  BUILD FOI EXECUTADO** (instrução do humano: "Primeiro executamos tudo depois testamos"). Pontos de teste ainda
  pendentes (para a tarefa de specs): Copilot create com `conversation_id` de A por B/membro (esperado 404, nada
  persistido/enfileirado); `ChatService` com `conversation_id` de A por B (contexto sem IDs); ferramentas
  `get_conversation`/`get_contact`/`search_contacts` com alvo de A por B (`not found` sem conteúdo);
  `agent_sessions#show` e `message_reports#create` com B/membro (esperado 404, sem reporte criado);
  `inbox_update` com admin nominal papel agente (esperado 401, nome intacto, sem `allow`); controles em inbox não
  marcada seguem 200.

## 5. Hooks instalados (resumo)

| Hook | Alvo | Ponto |
|---|---|---|
| `CopilotHook#connecta_scope_copilot_guard!` | `CopilotThreadsController`, `CopilotMessagesController` | `prepend_before_action` no `create` |
| `CopilotChatHook#current_viewing_history` | `Captain::Copilot::ChatService` | prepend, contexto do modelo |
| `CopilotToolHook#execute` | `GetConversationService`, `GetContactService`, `SearchContactsService` | prepend no `execute` |
| `CaptainHttpHook#authorize_conversation` | `AgentSessionsController`, `MessageReportsController` | prepend, antes do `authorize` nativo |
| `InboxHook#fetch_inbox` + `#check_authorization` + `#connecta_scope_inbox_create_guard!` | `InboxesController` | prepend + `prepend_before_action` no `create` |
| `rescue_from(Denied)` | 4 controllers Captain acima | 404 de leitura |

## 6. Specs c7b escritas em 2026-10-24 — NÃO EXECUTADAS (TASK_ID g0-t02-c7b)
- Arquivo próprio: `spec/connecta/captain_scope_spec.rb` — 32 exemplos (era 18). Nenhum spec executado nesta tarefa
  (runs reservados à validação consolidada). `ruby -c` passou com toolchain existente; `git diff --check` limpo.
- AC1: `agent_sessions#show` (B e membro sem grant sobre conversa A) e `message_reports#create` (idem) agora exigem
  404 sem vazar conteúdo e sem persistir reporte; `copilot_threads#create` e `copilot_messages#create` com
  `conversation_id` de A por B/membro exigem 404 sem `CopilotThread`/`CopilotMessage` novo e sem `ResponseJob`
  enfileirado; conversa inexistente na conta vira 404 sem revelar outra conta. Caracterizações de vazamento removidas.
  Positivos autorizados e controles de inbox não marcada mantidos (threads/messages sem `conversation_id`, thread com
  `conversation_id` de controle, sessão/reporte/FAQ/inbox_assistant de A, listagem vazia para B).
- AC2: `CopilotChatHook` via `Captain::Copilot::ChatService` real — alvo alheio de B/membro não entra no contexto
  (sem `Conversation ID`/`Contact ID`); A recebe o permitido; controle não marcado nativo. `CopilotToolHook` via
  serviços reais — `GetConversation`/`GetContact` com alvo de A por B devolvem `not found` exato;
  `SearchContacts` por nome de `contact_a` não expõe `contact_a` a B; autorizados devolvem o conteúdo permitido.
  Fixture `g0_scope_fixture` reusado; nenhum Gate stubado, nenhum transporte/modelo externo.
- PENDÊNCIA (outra spec, não editada aqui): `inbox_update` com admin nominal papel agente (401 nativo, nome intacto,
  sem `allow`) pertence a spec de inbox; listar na validação consolidada.

## 7. Correções pós-26 (TASK_ID g0-t02-c7b, 2026-10-24) — CÓDIGO CORRIGIDO, NÃO VALIDADO EM SPEC

Falhas-alvo da evidência 26 lote A Captain (10): `captain_scope_spec.rb:174,186,198` (threads, 404→500),
`:209,:220` (positivos, `CopilotThread.count` 0), `:238,:249` (messages, 404→500), `:306` (GetConversation
vazou `Conversation ID: #1`), `:320` (GetContact vazou `Contact ID: #19008`), `:334` (SearchContacts expôs
`Contact ID: #19020`). Log `26-logs/escopo-lote-a-1.log` não traz backtrace (só asserção; `show_exceptions`
renderiza 500). Causas isoladas por leitura do código nativo + hooks próprios (specs com setup correto,
NÃO editadas; Gate NÃO afrouxado; nenhum Gate stubado; sem reimplementar o sistema Captain):

- Causa 1 (7 falhas HTTP: 174/186/198/209/220/238/249) — ordem do callback em `installer.rb:60,62`.
  `prepend_before_action(:connecta_scope_copilot_guard!)` roda ANTES do `before_action :current_account`
  herdado (`Api::V1::Accounts::BaseController:4`, que preenche `Current.account` via
  `EnsureCurrentAccountHelper:4-7`). Com `Current.account == nil`, `CopilotHook:13`
  (`Current.account.conversations...`) levanta `NoMethodError` → 500 em TODOS os creates com
  `conversation_id` (negados que deviam dar 404 E positivos de A que deviam criar thread — conta 0).
  O mesmo padrão quebrou `CaptainTasksHook`? Não — tasks usa `before_action` comum (`installer.rb:58`) e por
  isso não falhou. Correção SÓ em `installer.rb`: trocar `prepend_before_action` por `before_action`
  (comum, `only: :create`) nos dois controllers Copilot. O guard passa a rodar DEPOIS de autenticação +
  `current_account` (401 nativo e conta certa preservados); a lógica do `CopilotHook` (blank→nativo,
  `nil?`→nativo, inexistente→404, marcada sem `read?`→404 com auditoria `copilot_conversation`) segue
  idêntica, sem conceder acesso extra. Comportamento unmarked preservado (retorno antes do Gate).
- Causa 2 (3 falhas de ferramentas: 306/320/334) — `self.class.name` sobrescrito pelo nativo.
  Cada ferramenta sobrescreve `def self.name` (`get_conversation_service.rb:2-4`,
  `get_contact_service.rb:2-4`, `search_contacts_service.rb:2-4`: `'get_conversation'`, `'get_contact'`,
  `'search_contacts'`), então `self.class.name` no `CopilotToolHook:16` devolve o NOME CURTO, nunca o FQCN
  `Captain::Tools::Copilot::*` que o `case` casava. O guard nunca rodava e o `super` (lookup direto por
  `account_id` nativo) devolvia o alvo alheio. Correção SÓ em `copilot_tool_hook.rb`: casar FQCN E nome
  curto (`'get_conversation'` → guard de conversa; `'get_contact'`/`'search_contacts'` → guard de contato).
  Decisão do guard inalterada (fail-closed sem `@user`; conversa via `ConversationQuery` do próprio `@user`;
  contato via `ContactVisibility` do próprio `@user`; texto `not found` sem ID/conteúdo). Sem afrouxar Gate,
  sem mascarar vazamento.
- NÃO alterados (verificados corretos após as duas correções): `copilot_hook.rb` (lógica do guard),
  `copilot_chat_hook.rb` (`current_viewing_history(conversation_id)` posicional confere com o nativo
  `chat_service.rb:100`; `connecta_scope_copilot_denied?` nega inexistente-em-outra-conta como `false`→`[]`
  só quando `find_by` é nil — sem marcar, sem vazar; marcada negada → `[]`), `captain_http_hook.rb`
  (`authorize_conversation` sem args confere com o nativo; agent_sessions/message_reports verdes na 26
  provam o caminho). Nenhum helper novo necessário. Specs de outro Coder (b1/team/b2) não lidos em mutação,
  não revertidos. `captain_scope_spec.rb` NÃO editado (setup comprovado correto pelos pontos acima).
- Arquivos próprios tocados: `app/services/connecta/scope/installer.rb` (2 linhas: ordem do callback
  Copilot) + `app/services/connecta/scope/copilot_tool_hook.rb` (`case` com nomes curtos). 5 hooks seguem
  instalados test-only (`Rails.env.test?`, prepend idempotente via `Installer.install!` nos specs).
- Execução pendente (NÃO executada nesta tarefa por instrução): specs `captain_scope_spec.rb` (33 casos)
  na próxima tarefa de validação; sem alegar teste verde. Validação aqui: `git diff --check` limpo;
  `git status --short` só `??` pré-existentes; `ruby -c` 3.4.4 absoluto OK nos 5 Ruby do escopo;
  `df -h /tmp` leitura (67%, sem apagar).
