# T0.2-c4 — notificações de conversas marcadas (G0, 2026-10-23)

**Pergunta:** notificações de conversas de inbox marcada chegam só a quem o `Connecta::Scope::Gate` permite ler?

**Resposta curta:**
- **Notificação (criação, nova mensagem, atribuição): não vaza para quem o Gate nega.** Agente B (outro setor) e membro sem grant não recebem; push e email também não são enfileirados para eles.
- **Dois vazamentos reais, ambos por caminho de menção ou de listagem, e um desvio do ADR 002:**
  - **ACHADO F1:** o admin nominal recebe notificação de conversa da inbox marcada.
  - **ACHADO F2:** menção a B em nota privada de A adiciona B como participante sem passar pelo Gate.
  - **ACHADO F3:** depois da menção, `GET conversations?conversation_type=participating` lista a conversa de A para B. Esse filtro troca a relação já filtrada pelo Gate.
- **Hipótese do briefing "a menção notifica B": não confirmada.** O builder barra a notificação (ver §3). O vazamento está em F2 e F3.

Nenhum código de app foi alterado. A correção fica para a c5.

Spec: `spec/connecta/scope_notifications_spec.rb` (11 exemplos, dados sintéticos, sem chamada externa). Logs: `.context/evidence/g0/13-logs/`.

## 1. Caminho verificado por leitura

| Etapa | Arquivo:linha | O que faz |
|---|---|---|
| Criação de conversa | `app/listeners/notification_listener.rb:16-28` | `conversation_created` cria `conversation_creation` para cada membro da inbox |
| Atribuição | `app/listeners/notification_listener.rb:30-48` | só com `notifiable_assignee_change` e responsável presente |
| Nova mensagem / menção | `app/listeners/notification_listener.rb:50-55` | chama `Messages::MentionService` e `Messages::NewMessageNotificationService` |
| Builder | `app/builders/notification_builder.rb:31`, `:52-63` | `return unless user_can_access_conversation?`, que chama `ConversationPolicy#show?` |
| Hook de policy | `app/services/connecta/scope/policy_hook.rb:4-6`; instalado em `app/services/connecta/scope/installer.rb:15` | em inbox marcada, `show?` vira `Gate#read?` |
| Gate | `app/services/connecta/scope/gate.rb:5` (`READ_PERMISSIONS` = acompanhar, atender), `:24` (admin nominal lê), `:32-37` (escopo, estado, grant) | decide leitura |
| Admin nominal | `app/services/connecta/scope/projection.rb:27-29` | `admin?` = grant `admin_nominal` com autenticação válida |
| Entrega | `app/models/notification.rb:58` (`after_create_commit`), `:30-39` (push em `:31`, email em `:36`) | push e email só para notificação criada |
| Menção | `app/services/messages/mention_service.rb:18` (participante), `:61` (admins + membros), `:69-81` (notificação pelo builder), `:87-91` (`find_or_create_by` sem Gate) | ver §3 |
| Listagem | `app/finders/conversation_finder.rb:116-126` (`PermissionFilterService` em `:119`, `filter_by_conversation_type` em `:124`), `:146-152` (`participating` em `:151-152` substitui a relação) | ver F3 |
| Filtro do Gate | `app/services/connecta/scope/conversation_query.rb:9-15`; `finder_hook.rb:3-5` | filtra a listagem antes da paginação |
| ADR | `.context/decisions/002-negacao-http-escopada-g0.md:12` | admin nominal não recebe linhas da inbox marcada na listagem; só detalhe auditado |

## 2. Resultado por caso (AC1, AC2)

Todos os exemplos abaixo passaram. Os controles positivos garantem que os negativos não passam por vazio.

| Caso | Usuário | Notificado? | Esperado (briefing) | Exemplo |
|---|---|---|---|---|
| Criação, conv. do setor A | agente A (grant `atender` em A) | sim | sim | criação, 1º exemplo |
| Criação, conv. do setor A | acompanhar (`manager_a`, grant em A) | sim | não citado | criação, 1º exemplo |
| Criação, conv. do setor A | agente B (grant só em B) | **não** | não | criação, 1º exemplo |
| Criação, conv. do setor A | membro sem grant | **não** | não | criação, 1º exemplo |
| Criação, conv. do setor A | admin nominal | **sim (F1)** | não | criação, ACHADO F1 |
| Controle: inbox não marcada | membro sem grant | sim (regra nativa) | sim | controle |
| Nova mensagem (responsável A, participante B) | A | sim (`assigned_conversation_new_message`) | sim | nova mensagem |
| Nova mensagem | B (participante) | **não** | não | nova mensagem |
| Atribuição a A | A | sim | sim | atribuição, 1º |
| Atribuição a B | B | **não** | não | atribuição, 2º |
| Push e email (criação) | A e acompanhar: enfileirados; B e membro sem grant: não | — | não | push e email |
| `GET notifications` | B não lista a conv. de A; A lista (controle) | — | não | listagem |

## 3. Menção (AC3)

Caso: nota privada de A (`sender` = agente A) com `[B](mention://user/<B>/<nome>)` na conv. do setor A.

| Efeito | Resultado | Exemplo |
|---|---|---|
| Notificação para B | **não gerada.** O builder chama `ConversationPolicy#show?`, que passa pelo Gate, e o Gate nega B | "menção … não gera notificação para B" (passou) |
| B vira participante da conversa | **sim, sem Gate** (`mention_service.rb:18`, `:87-91`) → **F2** | "ACHADO: a menção adiciona agente B como participante" (passou) |
| B lista a conversa do setor A | **sim** em `conversation_type=participating` (`conversation_finder.rb:124`, `:151-152`) → **F3** | "ACHADO: … lista a conversa de A para agente B" (passou; `GET` de B devolve `conv_a.display_id`) |

**Por que F3 existe:** o ramo `participating` faz `@conversations = current_user.participating_conversations.where(account_id:)`. Essa relação substitui o resultado de `PermissionFilterService` (que já passou pelo Gate), então o filtro de permissão deixa de valer nesse ramo. O ramo `mention` (`conversation_finder.rb:148-150`) usa `where(id:)` sobre a relação já filtrada e não tem o problema.

## 4. Achados

- **F1 (admin nominal recebe notificação).** `gate.rb:24` dá leitura ao admin nominal, e o builder aceita. O ADR 002 (`:12`) diz que a listagem não mostra linhas da inbox marcada; notificação é listagem. **Decisão humana:** (A) bloquear notificação para admin nominal na inbox marcada, alinhado ao ADR 002 — recomendo; ou (B) manter o admin como leitor e atualizar o ADR. Não corrigido aqui.
- **F2 (menção adiciona participante sem Gate).** `mention_service.rb:61` valida menção só por inbox/admin, e `:87-91` adiciona o participante antes do builder. Correção sugerida para a c5: validar a menção pelo Gate antes de `add_mentioned_users_as_participants`.
- **F3 (participating lista conversa fora do escopo).** `conversation_finder.rb:151-152` descarta o filtro de permissão. Correção sugerida para a c5: restringir o ramo `participating` à relação já filtrada, ou aplicar `ConversationQuery` nele. Sugestão de gotcha ao orquestrador (fora do IN-SCOPE desta task): registrar em `gotchas.md`.

## 5. Desvios em relação ao briefing

- "Admin nominal: não" → observado **sim** (F1). Asserção mantida com nome `ACHADO`, sem corrigir.
- "A menção notifica B" → observado **não** (builder barra); o vazamento real é F2 + F3.
- Número de exemplos: 11 (briefing: ~8). Os extras são os dois achados de menção e o controle de atribuição.

## 6. Não verificado

- Listagem `GET notifications` do admin nominal: não asserida. Pelo F1, provavelmente mostra a linha; não confirmado.
- Registros de auditoria (`AccessAudit`) gerados pela checagem do builder: `gate.rb:25-28` grava com `access_path: 'detail'` mesmo quando a checagem é de notificação. Só por leitura de código; o spec não cobre.
- Se `acompanhar` deve receber notificação: o spec segue `READ_PERMISSIONS` (`gate.rb:5`). Confirmar com o dono do produto.

## 7. Comandos e resultados

- Spec pelo runner travado (comando do briefing, com `> 13-logs/run-1-spec.log 2>&1`): exit **0**; `11 examples, 0 failures`; `Finished in 10.75 seconds`. Log: `13-logs/run-1-spec.log`.
- RuboCop com `env -i` e as variáveis `BUNDLE_*` do launcher: exit **0**; `1 file inspected, no offenses detected`. Log: `13-logs/rubocop-spec.log`.
- `git status --short`: sem arquivo rastreado alterado (só `??`, como no início). `git diff --check`: sem saída.
- Nenhum `--teardown`, `docker compose down`, `db:schema:load`, migração, comando remoto, leitura de `.env` ou commit.

## 8. T0.2-c5 — correção dos achados F1–F3 (2026-10-23)

Os exemplos `ACHADO` da c4 viraram asserções negativas. O código continua sendo spike instalado apenas em `Rails.env.test?`; nenhum arquivo do núcleo foi alterado.

### Correções

- **F1 — admin nominal sem notificação.** `NotificationHook` intercepta `NotificationBuilder#perform` somente quando o ator pertence a conversa de inbox marcada. `Gate#notifiable?` exige leitura de agente e exclui admin nominal; agentes com grant seguem a regra de leitura. Asserções cobrem criação, atribuição e destinatários de push/email (`gate.rb:21-24`, `notification_hook.rb:3-9`).
- **F2 — menção sem Gate é descartada para o usuário.** `MentionHook` filtra os IDs já validados nativamente antes da criação do job, do participante e da notificação. A mensagem permanece salva. Em inbox marcada, usuário sem leitura de agente (incluindo admin nominal) não vira participante, não ganha `Mention` quando o job pendente executa e não recebe notificação (`mention_hook.rb:6-12`; fluxo nativo em `mention_service.rb:11-20`). O controle em inbox não marcada confirma participante, `Mention` e notificação nativos.
- **F3 — `participating` volta a passar pelo escopo.** Depois que o ramo nativo substitui a relação, `ConversationFinderHook` reaplica `ConversationQuery` antes da paginação/contagem. Assim, até participante preexistente deixa de receber conversa de inbox marcada sem Gate; admin nominal também não a recebe na listagem (`conversation_finder_hook.rb:6-11`). O controle em inbox não marcada mantém a listagem nativa.
- `Installer.install!` registra os três hooks (`installer.rb:8,18,24-27`).

### Resultado final

| Validação | Resultado | Log |
|---|---|---|
| `scope_notifications_spec.rb` pelo runner travado com lock | exit **0**; **17 examples, 0 failures** | `13-logs/c5-run-3-notificacoes.log` |
| `scope_policy_query_spec.rb scope_http_filter_spec.rb` pelo runner travado com lock | exit **0**; **64 examples, 0 failures** | `13-logs/c5-run-4-regressao.log` |
| RuboCop com `env -i` e `BUNDLE_*` do launcher nos 6 `.rb` tocados pela c5 | exit **0**; **6 files inspected, no offenses detected** | `13-logs/c5-rubocop.log` |

A retomada preservou os logs anteriores: `c5-run-1-notificacoes.log` registrou 17 exemplos/1 falha no controle de `participating` (faltava acesso nativo à inbox antes de criar o participante); `c5-run-2-notificacoes.log` registrou o exemplo isolado verde. A execução completa final é a run 3 acima.
