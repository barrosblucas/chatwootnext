# T0.2-c8 — chat interno e conteúdo de conversa (G0, 2026-10-23)

**EVID-7 (chat interno): NÃO lê conteúdo de conversa.** Nenhum caminho do chat interno lê, incorpora, linka ou busca mensagem ou anexo do núcleo (`Conversation`, `Message` do núcleo). Só lê o próprio conteúdo: `InternalChat::Message` e `InternalChat::MessageAttachment`.

Escopo: `spec/connecta/internal_chat_scope_spec.rb` (6 exemplos). Dados sintéticos, banco `conecta_baileys_g0_test`, sem chamada externa. Nenhum código de app foi alterado.

## 1. Como foi verificado (AC1)

Busca por leitura, com `grep` (sem `rg` no PATH deste ambiente):

- `conversation` (sem diferenciar maiúsculas), `Conversation`, `display_id`, `conversation_id` e `/conversations` em `app/models/internal_chat`, `app/controllers/api/v1/accounts/internal_chat`, `app/services/internal_chat`, `app/policies/internal_chat`, `app/listeners/internal_chat_listener.rb`, `app/jobs/internal/setup_default_channels_job.rb` e `lib/tasks/internal_chat_search.rake`: **0 ocorrências**.
- `Message` sem o prefixo `InternalChat::` nesses mesmos caminhos: **0 ocorrências**. Todas as referências a `Message` são `InternalChat::Message`.
- `internal_chat` em `enterprise/`: **0 arquivos**.

O corte por grep é necessário, mas não basta. Os caminhos que leem conteúdo estão abaixo, um por um:

| Caminho | O que lê | Arquivo:linha |
|---|---|---|
| Busca (`GET /internal_chat/search`) | `InternalChat::Message` filtrado por canais acessíveis; mínimo de 3 caracteres | `app/controllers/api/v1/accounts/internal_chat/search_controller.rb:2-11`; `app/services/internal_chat/search_service.rb:14`, `:75-80` (`ILIKE` em `internal_chat_messages.content`), `:109-119` (`accessible_channels`) |
| Listagem de mensagens do canal | `current_channel.messages` (só do canal) | `app/controllers/api/v1/accounts/internal_chat/messages_controller.rb:9-16`, `:109-114` (`base_messages_scope`), `:135-151` (`message_response`) |
| Resposta por `parent_id` | `channel.messages.exists?(id:)`: o pai tem de estar no mesmo canal | `app/services/internal_chat/message_create_service.rb:7`, `:46-48` |
| Reação (`/internal_chat/messages/:message_id/reactions`) | `InternalChat::Message` da conta, por `find` | `app/controllers/api/v1/accounts/internal_chat/reactions_controller.rb:4`, `:32-34` |
| Anexos (download/URL) | `InternalChat::MessageAttachment`; `file_url` vem do anexo interno | `messages_controller.rb:178-185`; `channels_controller.rb:390`, `:471-477`; `message_create_service.rb:50-57`; `app/models/internal_chat/message_attachment.rb:24-28` |
| Enquetes | mensagem interna (`content_type: poll`) | `app/controllers/api/v1/accounts/internal_chat/polls_controller.rb:127-135` |
| Menções | regex sobre o texto da mensagem interna | `app/services/internal_chat/mention_service.rb:5`, `:13-14`; `app/services/internal_chat/notification_service.rb:19-20` |
| Notificações | `primary_actor` = canal interno; `secondary_actor` = mensagem interna | `app/services/internal_chat/notification_service.rb:45-53`; tipos `internal_chat_mention` e `internal_chat_new_message` em `app/models/notification.rb:106-107` |
| Eventos e webhooks | payload da mensagem interna e anexos internos | `app/listeners/internal_chat_listener.rb:135-140`, `:173-179` |
| Modelo da mensagem | associações só com `InternalChat::*`; sem campo que aponte para conversa | `app/models/internal_chat/message.rb:38-48`, `:57-58` |
| Canal | `messages` e `message_attachments` só internos | `app/models/internal_chat/channel.rb:54-59` |

Não encontrei caminho de compartilhamento, citação ou link para conversa. O texto de uma mensagem interna pode conter uma URL digitada pelo usuário; isso é texto livre, não leitura do núcleo.

## 2. Resultado da análise (EVID-7)

| Pergunta | Resposta | Prova |
|---|---|---|
| O chat interno lê conteúdo de conversa? | **Não** | seção 1: 0 referências ao núcleo nos caminhos listados |
| Algum caminho aceita id de conversa? | **Não** | nenhum parâmetro `conversation_id`/`display_id` nas rotas internas (`config/routes.rb:195-226`) |
| Algum caminho aceita id de mensagem do núcleo? | **Sim, em 2 caminhos, e ambos rejeitam**: `parent_id` (`message_create_service.rb:46-48`, RecordNotFound) e reação (`reactions_controller.rb:33`, `find` só em `InternalChat::Message`) | exemplos 5 e 6 da spec |
| A busca interna cobre a inbox marcada? | Não cobre conteúdo do núcleo; a busca não consulta `Conversation` nem `Message` do núcleo | `search_service.rb:75-80` |

Limitação: a leitura é estática. Caminhos sem exemplo na spec (`threads`, `pin`, `drafts`, `categories`, `channel_members`, `polls`, edição e remoção de mensagem) foram checados só por grep, sem teste.

## 3. Exemplos da spec (AC3)

Arquivo: `spec/connecta/internal_chat_scope_spec.rb`.

| # | Exemplo | Tipo |
|---|---|---|
| 1 | agente B: busca `segredoalfa` não devolve mensagem nem o texto da conversa marcada | característica (busca) |
| 2 | membro sem grant: mesma busca, mesma resposta | característica (busca) |
| 3 | controle positivo: busca acha a mensagem interna com o mesmo termo e não traz a da conversa | controle |
| 4 | agente B: listagem do canal público só tem conteúdo interno | característica (listagem) |
| 5 | `parent_id` com id de mensagem da conversa: 404 e nada gravado | negativa (id de mensagem) |
| 6 | reação em id de mensagem da conversa: 404 e nada gravado | negativa (id de mensagem) |

Nenhum caminho aceita id de conversa, então não há exemplo negativo de conversa; os exemplos 1, 2 e 4 são as caracterizações de índice e busca pedidas.

## 4. Resultados

| Verificação | Comando | Resultado | Log |
|---|---|---|---|
| RuboCop da spec | `env -i` com `PATH` do toolchain 3.4.4 e `BUNDLE_GEMFILE`, `BUNDLE_PATH`, `BUNDLE_FROZEN=true` (`bundle exec rubocop spec/connecta/internal_chat_scope_spec.rb`) | 1 arquivo, 0 ofensas, exit 0 | `12-logs/rubocop-spec.log` |
| Spec pelo runner, com lock | `flock -w 900 .../spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/internal_chat_scope_spec.rb` | **6 exemplos, 0 falhas**, exit 0 | `12-logs/run-1-spec.log` |

A execução esperou o lock até outro Coder liberar `scope_policy_query_spec.rb`; não houve `rspec` concorrente no banco durante a execução do spec.

Aviso no log, sem relação com a spec: deprecação do `Rails.application.secrets`, do `assigned_conversations` no `User` (chamado pelo fixture, `g0_scope_fixture.rb:20`) e do `fixture_path`. Nenhum é erro.

Limitação: a spec prova o comportamento nos caminhos da seção 3. Ela não cobre os demais caminhos da seção 1 (por exemplo `threads`, `pin`, `drafts`), que estão só por leitura.
