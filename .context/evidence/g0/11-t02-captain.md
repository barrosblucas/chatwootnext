# T0.2-c7 — rotas Captain que leem conversa (G0, 2026-10-23)

**Estado: BLOCKED.** Spec pronta e RuboCop limpo. A spec ficou verde em 2 de 5 execuções pelo runner; as outras 3 falharam com a mesma spec e o mesmo código. A causa não foi identificada (seção 4). Há um vazamento real em rotas Copilot, registrado como caracterização (seção 2).

Escopo: `spec/connecta/captain_scope_spec.rb` (18 exemplos). Dados sintéticos, banco `conecta_baileys_g0_test`, sem chamada a provedor de IA (`RubyLLM.chat` é espião sem retorno, rede bloqueada pelo `spec_helper`). Nenhum código de app foi alterado.

Enterprise carregada no teste: `ChatwootApp.enterprise?` é `root.join('enterprise').exist?` (`lib/chatwoot_app.rb:14-17`). Nesta worktree a condição vale, e as respostas 200 das rotas Copilot e FAQ (controllers só em `enterprise/`) confirmam que o código é alcançado.

## 1. Rotas cobertas (leitura de conversa, exceto `captain/tasks`)

| Rota | Mecanismo de leitura | Negativa (B / membro sem grant) | Positivo / controle | Resultado |
|---|---|---|---|---|
| `GET captain/agent_sessions/:message_id` | `authorize @message.conversation, :show?` (`enterprise/app/controllers/api/v1/accounts/captain/agent_sessions_controller.rb:22-23`) → `PolicyHook#show?` (`app/services/connecta/scope/policy_hook.rb:3-6`) | **401** nativo (Pundit, `request_exception_handler.rb:24-27`). Decisão 002 pede 404; ver divergência, seção 3 | A com grant: 200 | exemplos 1–3; verdes nas runs 4 e 5 (seção 4) |
| `POST captain/message_reports` | `ensure_cloud_installation` (`message_reports_controller.rb:17-18`, `ChatwootApp.chatwoot_cloud?` stubado) → `authorize @message.conversation, :show?` (`:25-26`) → `PolicyHook` | **401**, nenhum `Captain::MessageReport` criado (B e membro) | A com grant: cria 1 reporte | exemplos 4–6; verdes nas runs 4 e 5 |
| `GET captain/faq_suggestions` (index) | `set_accessible_suggestions` (`faq_suggestions_controller.rb:60-61`) → `Captain::FaqSuggestionFinder#perform` (`app/finders/captain/faq_suggestion_finder.rb:11-14`) → `Conversations::PermissionFilterService` (`:19-21`) → `FinderHook` (`app/services/connecta/scope/finder_hook.rb:3-5`) → `ConversationQuery` (`conversation_query.rb:9-14`) | B: lista vazia (`total_count` 0, sem a pergunta no corpo); membro: não lista | A: lista a sugestão de A e a de controle | exemplos 7 e 11; verdes nas runs 4 e 5 |
| `GET captain/faq_suggestions/:id` (show) | `set_suggestion` usa o finder (`faq_suggestions_controller.rb:64-65`); observações filtradas por `accessible_conversations` (`:18-19`, `:68-69`) | **404** (RecordNotFound do finder), pergunta ausente do corpo | A: 200 com a pergunta | exemplos 8 e 10; verdes nas runs 4 e 5 |
| `POST captain/faq_suggestions/:id/approve` | `set_suggestion` (`faq_suggestions_controller.rb:64-65`) antes de `FaqSuggestionApprovalService` (`:32-35`) | **404**, nenhum `Captain::AssistantResponse` criado (membro) | — | exemplo 9; verde nas runs 4 e 5 |
| `GET conversations/:id/inbox_assistant` | `before_action :conversation` (`app/controllers/api/v1/accounts/conversations_controller.rb:6`) → `conversation` com `authorize` (`:213-215`) → `ConversationHttpHook#conversation` (`app/services/connecta/scope/conversation_http_hook.rb:7-13`, rescue → `Denied` 404). Ação: `enterprise/app/controllers/enterprise/api/v1/accounts/conversations_controller.rb:4-11` (só o nome do assistente da inbox) | **404** (B e membro) | A com grant: 200 (`assistant: nil`); controle (inbox não marcada): 200 | exemplos 12–15; verdes nas runs 4 e 5 |

Dois exemplos são **CARACTERIZAÇÃO DE VAZAMENTO**; eles afirmam o comportamento atual, não o correto:

| Rota | Mecanismo | Achado |
|---|---|---|
| `POST captain/copilot_threads` | `copilot_thread_params` aceita `conversation_id` (`enterprise/app/controllers/api/v1/accounts/captain/copilot_threads_controller.rb:51-52`); `build_copilot_response` enfileira com esse id (`:32-35`) → `CopilotMessage#enqueue_response_job` (`enterprise/app/models/copilot_message.rb:40-48`) → `Captain::Copilot::ResponseJob` (`enterprise/app/jobs/captain/copilot/response_job.rb:3-16`) | B cria thread com `conversation_id` de A **sem checagem de escopo**; o job sai com esse id |
| `POST captain/copilot_threads/:id/copilot_messages` | `enqueue_response_job(params[:conversation_id], …)` (`enterprise/app/controllers/api/v1/accounts/captain/copilot_messages_controller.rb:13-18`) | Membro sem grant faz o mesmo em thread própria |
| Contexto do modelo (`Captain::Copilot::ChatService`) | `@conversation = @account.conversations.find_by(display_id:)` (`enterprise/app/services/captain/copilot/chat_service.rb:14`); `current_viewing_history` (`:100-113`) põe **ID da conversa e ID do contato de A** no contexto enviado ao modelo | Metadados de A chegam ao modelo sem checagem. Os exemplos não chamam o modelo (`RubyLLM.chat` não recebe chamada) |

Não verificado: as ferramentas Copilot (`build_tools`, `chat_service.rb:63-76`: `GetConversationService`, `SearchConversationsService`, `GetContactService`, `SearchContactsService`) rodam com `user: @user` (B). Não sei se respeitam o escopo. Não foi testado.

## 2. Rotas sem leitura de conversa (fora do escopo desta spec)

- `captain/copilot_threads#index` e `copilot_messages#index`: listam só threads do próprio usuário (`copilot_threads_controller.rb:4-11`).
- `captain/assistant_responses`, `assistants` (inclui `playground`, `metrics`, `summary`, `drilldown`), `bulk_actions`, `custom_tools`, `documents`, `scenarios`, `inboxes`, `preferences`: sem referência a `conversation` nos controllers (grep).
- `captain/faq_suggestions#update` e `#dismiss`: usam o mesmo `set_suggestion` do approve (`faq_suggestions_controller.rb:64-65`), mas não têm exemplo próprio.

## 3. Divergência com a decisão 002

`agent_sessions#show` e `message_reports#create` não estão no `install_denied_rendering!` (`app/services/connecta/scope/installer.rb:54-61`). A negação fica em 401, não em 404 (leitura). O 401 confirma que a mensagem existe; para mensagem inexistente o retorno é 404. É vazamento de existência, não de conteúdo. A spec registra o 401 com o nome do exemplo. Não foi corrigido (fora de escopo).

## 4. Resultados por execução (`spec/connecta/captain_scope_spec.rb`)

| Execução | Log | Exit | Resultado | Observação |
|---|---|---|---|---|
| 1 | `11-logs/run-1-captain-scope.log` | 1 | 18 ex, 7 falhas: L62, L70, L99, L107, L114, L139, L145 | B e membro passam pela rota e veem dados que deveriam ser negados (FAQ, inbox); membro aprovou (1 `AssistantResponse`). Logs mostram sessões com 401 OK |
| debug (1 exemplo, spec temporária, removida) | `11-logs/debug-tmp.log` | 0 | B: show 404, inbox_assistant 404, FAQ vazio, reporte 401 | Mesmo código, sem falha |
| debug (cópia da spec com `warn`, removida) | `11-logs/debug2-tmp.log` | 0 | 18 ex, 0 falhas | `gate.read?(conv_a)=false`, `query_b=[3, 6]` (conv_b e controle) |
| 2 | `11-logs/run-2-captain-scope.log` | 1 | 18 ex, 1 falha: L107 | `ActiveRecord::RecordNotUnique` no fixture (`g0_scope_fixture.rb:13`): `index_channel_whatsapp_on_phone_number` com `+12345678981` já commitado no banco compartilhado |
| 3 | `11-logs/run-3-captain-scope.log` | 1 | 18 ex, 9 falhas: L33, L39, L62, L70, L99, L107, L114, L139, L145 | Inclusive sessões: B recebeu 200 (era 401 na run 1) |
| 4 | `11-logs/run-4-captain-scope.log` | 0 | 18 ex, 0 falhas | — |
| 5 (final, após RuboCop) | `11-logs/run-5-captain-scope.log` | 0 | 18 ex, 0 falhas | — |

Execuções concorrentes na mesma worktree e no mesmo banco (verificadas com `ps`): `scope_policy_query_spec`, `transfer_cutover_spec`, `scope_socket_spec` (outros Coders). Durante a run 1 e a run 3, outros Coders alteraram `socket_hook.rb` (01:36:04), `installer.rb` (01:36:08), `transfer/*` (01:37–01:42) e `transfer_cutover_spec.rb` (01:41:12). Não toquei nesses arquivos.

Causa: **não identificada**. Descartado: a lógica da spec (execuções 4 e 5 e a cópia de depuração passaram com o mesmo corpo de teste); o `installer.rb` atual mantém `ConversationPolicy`/`PermissionFilterService` iguais aos que li no início (`installer.rb:15-16`). Não descartado: interferência entre processos no banco compartilhado (a run 2 mostrou dado commitado por outro processo). Para confirmar: rodar 3 vezes seguidas, sem outro `rspec` ativo (`ps -eo args | grep rspec`), ou em banco isolado.

## 5. Pendências

- Estabilidade: a spec não serve como gate enquanto as runs 1 e 3 não forem explicadas.
- Vazamento Copilot (seção 1): precisa de correção (checagem de escopo sobre `conversation_id` em `copilot_threads#create` e `copilot_messages#create`), fora desta tarefa.
- 401 em `agent_sessions#show` e `message_reports#create` (seção 3): decidir se vira 404 (decisão 002) ou se a decisão é revista.
- Ferramentas Copilot com `user: @user` (seção 1): não verificadas.
- `message_reports` roda com `chatwoot_cloud?` stubado; em produção a rota é 404 fora da nuvem.
