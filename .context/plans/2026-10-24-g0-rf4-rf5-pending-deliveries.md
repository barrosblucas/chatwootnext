# G0 · RF4/RF5 — revalidar notificações existentes e entregas pendentes (spike, só teste) · rev. 2

Escopo: só REQUIRED_FIXES 4 e 5 do Juiz T2 (`/home/thanos/.local/state/codex-judge/20261024T192516-1387110/verdict.md`).
Rev. 2 fecha as lacunas do sênior: R1 (`contact.deleted` legado ambíguo), R2 (`AdminMetadataBroadcastJob` sem revalidação),
R3 (`ActionMailer::MailDeliveryJob` já enfileirado). Tudo instalado só por `Connecta::Scope::Installer.install!` (`installer.rb:7` →
`Rails.env.test?`). Sem tabela, coluna, tombstone, migração, SQL ou produção. `notifications` nunca é apagada.

**Blocos A–F são agrupamentos internos.** Cada "check" é só a lista de specs/lint que o Coder confere. **Não há Juiz entre blocos.**
O único Juiz é o **Gate G0**, depois de RF1..RF6 concluídos (regra de batch do orquestrador).

## 0. Fatos (verificados; `AM` = `.bundle/gems/ruby/3.4.0/gems/actionmailer-7.1.5.2/lib/action_mailer`, `AJ` = idem `activejob-7.1.5.2/lib/active_job`)

| Superfície | Fonte | Fato |
|---|---|---|
| Notificação | `notification_hook.rb:3-9`; `notification_finder.rb:13-29,39-41`; `notifications_controller.rb:5,71-73` | Gate só na criação; lista/contagem saem de `@notifications`; `fetch_notification` fora do finder. |
| Enqueue push/email | `app/models/notification.rb:58,183-191` | `after_create_commit` → `PushNotificationJob/EmailNotificationJob.perform_later(self)`. Push envia inline (`push_notification_service.rb:66-69`). |
| Email | `email_notification_service.rb:20-24`; `AM/parameterized.rb:146-152`; `AM/mail_delivery_job.rb:21-29` | `deliver_later` → `MailDeliveryJob(mailer, action, 'deliver_now', params: {account:}, args: [conv, agent, x])`. |
| Ponto final do email | `AM/message_delivery.rb:123-129`; `AM/callbacks.rb:9,15-17`; `AM/base.rb:650-659` | `deliver_now` → `run_callbacks(:deliver) { message.deliver }`; `before_deliver` vê `to`/`subject` prontos; ação sem `mail` = `NullMail`. |
| Mailer | `conversation_notifications_mailer.rb:2-62`; `enterprise/.../conversation_notifications_mailer.rb:2-32` | 5 ações OSS + 3 SLA setam `@conversation`/`@agent` e chamam `send_mail_with_liquid(to: @agent.email, ...)`. Único chamador: `email_notification_service.rb:21`. |
| Broadcast | `action_cable_listener.rb:4-14,355-363`; `action_cable_broadcast_job.rb:13-18,25-30` | Listener enfileira `(tokens, event, payload)`; job relê a conversa em `CONVERSATION_UPDATE_EVENTS`. Chamadores diretos: `internal_chat_listener.rb:199`, `branding_enrichment_job.rb:33`. |
| Admin metadata | `admin_metadata_broadcast_job.rb:6-10`; `socket_hook.rb:84-85,111-115` | Tokens de admin crus; execução sem checagem (R2). |
| Contato | `socket_hook.rb:89-101`; `contact_lifecycle_hook.rb:14-38`; `contact.rb:61-62,74` | `destroy_async` de vínculos; `contact.deleted` em `after_destroy_commit`; snapshot `{contact_id, account_id, tokens}`. |
| Contrato do snapshot | `scope_team_contact_spec.rb:258,307` | Chaves exatas `contact_id, account_id, tokens`; não marcado → `nil`. **Não pode mudar** (rev. 1 C4 quebrava). |
| Gate/epoch | `gate.rb:22-24,29,37-42`; `projection.rb:19-29`; `g0_scope_schema.rb:52-59,73-74` | `read?` = true para admin nominal; epoch nunca comparado; `ConversationScope` tem `inbox_id`/`contact_id`. |
| Enqueue síncrono | `AJ/enqueuing.rb:56-58,87-108`; `rg enqueue_after_transaction_commit AJ` = 0 | `perform_later` → `enqueue` → `queue_adapter.enqueue self` (chama `serialize`) na thread do chamador. |
| Retry/execução | `AJ/exceptions.rb:157-160`; `AJ/execution.rb:26-31`; `AJ/queue_adapters/test_adapter.rb:39-54` | `retry_job` → `enqueue` na mesma instância; `execute` → `deserialize` → `perform_now`. |
| Sem atalho | `rg "(PushNotificationJob\|EmailNotificationJob\|ActionCableBroadcastJob\|AdminMetadataBroadcastJob)\.(perform_now\|new)" app lib enterprise` = 0 | Todo envio passa por `enqueue`. `DeserializationError` → descarta (`application_job.rb:3-7`). |
| Specs que leem `args` | `scope_socket_spec.rb:24-35`; `scope_team_contact_spec.rb:228-232` | Args nativos dos dois jobs de broadcast não podem mudar. |

## 1. Abordagem

### 1.1 Binding comum e ponto exato de captura
- Contexto = hash de chaves string e valores primitivos na chave extra `'connecta_scope'` do job serializado (`AJ/core.rb:139-146`).
- `Connecta::Scope::DeliveryBinding` (prepend): `enqueue` captura **antes do `super`** se `@connecta_scope_captured` não está setado;
  `serialize` só escreve o ivar; `deserialize` restaura e marca capturado (sem chave = legado).
- Trace (captura na thread do evento, antes do handoff ao adaptador):
  - notificação: `notification.rb:183-191` → `AJ/enqueuing.rb:57` → `DeliveryBinding#enqueue` lê `arguments.first` → adapter → `serialize`.
  - socket: `SocketHook#broadcast` → `DeliveryContext.with(ctx, 'ActionCableBroadcastJob') { super }` → `action_cable_listener.rb:363` → `enqueue` → `take`.
  - admin: `SocketHook#broadcast` → `with(ctx, 'Connecta::Scope::AdminMetadataBroadcastJob') { perform_later }` → `take`.
  - email: `NotificationDeliveryGuard#perform` → `with(ctx, MAILER) { super }` → `deliver_now` (B2) → `before_deliver` → `take(MAILER)`.
- Não depende de thread limpa: `take` exige alvo = nome da classe e é de uso único; `with` restaura em `ensure`; enqueue fora de `with`
  recebe `{'v'=>1,'kind'=>'unbound'}`. Em 7.1.5.2 não há `enqueue_after_transaction_commit`; adaptador que adie o push já acha o ivar pronto.
- Retry: `retry_job` → `enqueue` na instância desserializada → sem recaptura; retry do Sidekiq reusa o JSON (B3 caso 8, F1 caso 7).

### 1.2 Regras de execução (antes de qualquer I/O e antes do reload do payload)
Recebe só quem: estava no contexto; tem epoch atual igual ao capturado e não revogado; não é admin nominal **hoje** (exclusão explícita,
porque `gate.rb:29` dá `read?` a ele); passa no Gate/visibilidade de hoje. Token relido de `user.pubsub_token`. Só filtra; nunca adiciona.

| `kind` | Chaves | Nasce | Execução |
|---|---|---|---|
| `notification` | `account_id, conversation_id, notification_id, user_id, epoch` | B1b, C3 | `notification_deliverable?` |
| `conversation` | `account_id, conversation_id, users [[id, epoch]], contact_inbox_ids` | C3 | epoch ∧ ¬admin ∧ `Gate#read?('socket_job')`; widget por `contact_inbox_ids` |
| `contact` | `account_id, contact_id, users` | K3 | epoch ∧ ¬admin ∧ `ContactVisibility.visible_scope` |
| `contact_deleted` | `account_id, contact_id, users, scope_ids` | K3 | epoch ∧ ¬admin ∧ `Gate#scope_readable?` em algum `scope_ids` |
| `contact_ambiguous` | `account_id, contact_id` | K3 | nada |
| `native` | `account_id`, opc. `inbox_id`/`contact_id` | C3, K3 | nativo, salvo `inbox_id` marcado agora ou `contact_id` vinculado agora |
| `unbound` | — | enqueue fora do `SocketHook` | nativo, salvo payload com `inbox_id` marcado |
| `admin_metadata` | `account_id, admins [[id, 'native'\|'nominal', epoch]]` | E1 | `epoch_same?` ∧ papel capturado ainda vale |
| sem chave | — | job anterior à instalação | §1.3 |

### 1.3 Legado e limite de disponibilidade (R1)
- `ActionCableBroadcastJob` sem chave: conta do payload sem inbox marcada → nativo. Com inbox marcada: só passa evento fora de
  `CONTACT_EVENTS` cujo `inbox_id` (payload, `conversation.inbox_id` ou `notification.primary_actor.inbox_id`) é **não** marcado; o resto é
  negado, inclusive `contact.*` com vínculo já apagado. Sem `account_id` e com alguma inbox marcada → negado.
- Push/email sem chave em conversa marcada → nada. `MailDeliveryJob` de conversa marcada sem contexto → `throw :abort`.
  `AdminMetadataBroadcastJob` sem contexto → nada (classe só existe sob o spike).
- **Limite:** jobs legados de contato ou não resolvíveis, em conta com inbox marcada, são perdidos uma vez, na instalação. São só avisos de
  UI em tempo real; a próxima chamada HTTP mostra o estado certo. Nenhuma mensagem de entrada do cidadão é descartada. Eventos novos não
  marcados levam `native` explícito e seguem entregues.

### 1.4 Email marcado (R3)
- Futuro: marcado vira `deliver_now` dentro do job guardado (B2); não nasce `MailDeliveryJob` marcado.
- Pendente: `before_deliver` no `ConversationNotificationsMailer` é o último ponto antes do SMTP nos dois caminhos. Marcado exige
  contexto `notification` da thread, mesmo usuário/conversa, `message.to == [user.email]` atual e `notification_deliverable?` relido ali.

## 2. Execução

Spec (único comando permitido; `<SPECS>` = caminhos do passo):

```
cd /home/thanos/chatwootnext-connecta-g0-prep && PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH flock -w 900 /home/thanos/.cache/connecta-g0-test/spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply <SPECS>
```

Lint: `PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:/usr/bin:/bin HOME="$HOME" LANG=C.UTF-8 BUNDLE_GEMFILE=/home/thanos/chatwootnext-connecta-g0-prep/Gemfile BUNDLE_PATH=/home/thanos/chatwootnext-connecta-g0-prep/.bundle/gems BUNDLE_FROZEN=true bundle exec rubocop <ARQUIVOS>`

`--apply` exige a autorização humana já registrada para o alvo G0; sem ela, dry-run e parar. `R=/home/thanos/chatwootnext-connecta-g0-prep`.
Linhas citadas = estado atual, antes do passo. `installer.rb` (A1, A2, B1b, B2, M1, C2) e `socket_hook.rb` (C3, K3, E1): passos sequenciais.
Nenhum passo toca `copilot_tool_hook.rb`, Captain, `app/services/connecta/transfer/*` ou arquivos de LocalTransaction/Activation (RF1/RF6).
Specs aprovadas (`scope_socket_spec.rb`, `scope_team_contact_spec.rb`, `scope_notifications_spec.rb`) **não são editadas**.

### Bloco A — RF4 HTTP: ocultar notificações existentes

**A1 · código · filtro antes da paginação** (≈15 min) — **primeiro passo do Coder**
- Criar `$R/app/services/connecta/scope/notification_visibility.rb`: `module_function filter(relation, user, account)`.
  - `marked = Projection.marked_inbox_ids`; vazio → devolve `relation`. `marked_convs = account.conversations.where(inbox_id: marked)`.
  - `visible = Projection.new(user).admin? ? Conversation.none : ConversationQuery.new(marked_convs, user).perform` (admin antes: sem `AccessAudit`).
  - Devolve `relation.where.not(primary_actor_type: 'Conversation')`
    `.or(relation.where(primary_actor_type: 'Conversation').where.not(primary_actor_id: marked_convs.select(:id)))`
    `.or(relation.where(primary_actor_type: 'Conversation', primary_actor_id: visible.select(:id)))`.
- Criar `$R/app/services/connecta/scope/notification_finder_hook.rb`: `private def find_all_notifications; super; @notifications = NotificationVisibility.filter(@notifications, current_user, current_account); end`.
- `$R/app/services/connecta/scope/installer.rb:28-31` (`install_notifications_and_mentions!`): `NotificationFinder.prepend(Connecta::Scope::NotificationFinderHook)`.
- Aceite: `notifications`, `count`, `unread_count` e contagens do socket (`action_cable_listener.rb:5,11,23-28`) filtrados. Sem `delete`/`update`.
- Check: lint dos 3 arquivos; spec em A3.

**A2 · código · ação em notificação oculta = 404** (≈10 min) — depende de A1
- Criar `$R/app/services/connecta/scope/notifications_controller_hook.rb`: `private def fetch_notification; super; raise ActiveRecord::RecordNotFound unless NotificationVisibility.filter(Notification.where(id: @notification.id), current_user, Current.account).exists?; end`.
- `installer.rb` (mesmo método): `Api::V1::Accounts::NotificationsController.prepend(Connecta::Scope::NotificationsControllerHook)`.
- Aceite: PATCH/snooze/unread/DELETE em oculta → 404 sem alterar a linha; visível → nativo. `read_all` (`update_all`) fica nativo.
- Check: lint; spec em A3.

**A3 · spec · `$R/spec/connecta/scope_notification_visibility_spec.rb` (novo)** (≈15 min) — depende de A1, A2 · ‖ B1a
- Cabeçalho idêntico a `$R/spec/connecta/scope_notifications_spec.rb:1-13`; `create(:notification, user:, account:, primary_actor: conv)`.
- Casos (com `GET .../notifications` e `GET .../notifications/unread_count`): 1. A com 16 de `conv_a` + 1 de `conv_control`; revoga
  grant → só a de controle, `meta.count`=1, `unread_count`=1, página 2 vazia. 2. transferência (`org_unit_id: org_b.id`) e
  `state: 'transferred_out'` → oculta. 3. `revoked_locally_at` → oculta. 4. admin nominal não lista e não grava `AccessAudit`
  `access_path: 'list'`. 5. controle: membro sem grant com `conv_control` → lista. 6. `Notification.where(user: A).count` inalterado.
  7. PATCH em oculta → 404 e `read_at` nil; visível → 200.
- Check: spec com `spec/connecta/scope_notification_visibility_spec.rb spec/connecta/scope_notifications_spec.rb`.

**Check A (sem Juiz):** A1–A3 verdes; lint dos 4 arquivos; `git diff --check`.

### Bloco B — RF4 entrega: push/email pendentes

**B1a · código · `DeliveryContext`** (≈15 min) ‖ A3
- Criar `$R/app/services/connecta/scope/delivery_context.rb` (`module_function`; `KEY = :connecta_scope_delivery_context`;
  `MAILER = 'AgentNotifications::ConversationNotificationsMailer'`):
  - `epoch_of(user_id)` → `UserAuthEpoch.find_by(user_id:)&.epoch`.
  - `epoch_current?(user_id, epoch)` → `epoch.is_a?(Integer) && UserAuthEpoch.exists?(user_id:, epoch:, revoked_locally_at: nil)`.
  - `epoch_same?(user_id, epoch)` → `epoch.nil? ? !UserAuthEpoch.exists?(user_id:) : epoch_current?(user_id, epoch)` (admin nativo sem linha).
  - `notification_conversation(n)` → `n.primary_actor` se `primary_actor_type == 'Conversation'`, senão nil.
  - `for_notification(n)` → nil se conversa nil/não marcada; senão `{'v'=>1,'kind'=>'notification','account_id','conversation_id','notification_id','user_id','epoch'=>epoch_of(n.user_id)}`.
  - `notification_deliverable?(ctx, n)` → hash, `v == 1`, `kind == 'notification'`, ids batem com o registro atual
    (`conversation_id == primary_actor_id`), `epoch_current?`, `Gate.new(n.user).notifiable?(conversa)`.
  - `with(ctx, target)`: grava `{'target'=>target,'ctx'=>ctx}` em `ActiveSupport::IsolatedExecutionState[KEY]`, `yield`, `ensure` restaura o anterior.
  - `take(target)`: só se `entry['target'] == target` e sem `entry['taken']`; grava `entry.merge('taken'=>true)`; devolve `entry['ctx']`.
- Check: lint; specs em B3/M2/F*.

**B1b · código · binding + guard dos jobs de notificação** (≈15 min) — depende de B1a
- Criar `$R/app/services/connecta/scope/delivery_binding.rb`:
  `def enqueue(options = {}); unless @connecta_scope_captured; @connecta_scope_context = connecta_scope_capture; @connecta_scope_captured = true; end; super; end`;
  `def serialize; super.tap { |d| d['connecta_scope'] = @connecta_scope_context if @connecta_scope_context }; end`;
  `def deserialize(job_data); super; @connecta_scope_context = job_data['connecta_scope']; @connecta_scope_captured = true; end`.
- Criar `$R/app/services/connecta/scope/notification_delivery_guard.rb`: `private def connecta_scope_capture` →
  `DeliveryContext.for_notification(arguments.first)`; `perform(notification)`: sem contexto **e** conversa nil/não marcada → `super`;
  senão `return unless notification_deliverable?(ctx, notification)`; `DeliveryContext.with(ctx, DeliveryContext::MAILER) { super }`.
- `installer.rb:28-31`: `[Notification::PushNotificationJob, Notification::EmailNotificationJob].each { |job| job.prepend(Connecta::Scope::DeliveryBinding); job.prepend(Connecta::Scope::NotificationDeliveryGuard) }` (guard por último, resolve `connecta_scope_capture`).
- Aceite: marcado sem chave não envia; contexto de outro usuário não envia; não marcado sem contexto = nativo.
- Check: lint; spec com `spec/connecta/scope_notifications_spec.rb` (inalterada, verde).

**B2 · código · email marcado sem novo job** (≈10 min) — depende de B1b
- Criar `$R/app/services/connecta/scope/email_delivery_hook.rb` (prepend em `Notification::EmailNotificationService`, sobrescreve
  `send_notification_email` de `email_notification_service.rb:20-24`): conversa marcada → mesma chamada com `.deliver_now`; senão `super`.
- `installer.rb:28-31`: `Notification::EmailNotificationService.prepend(Connecta::Scope::EmailDeliveryHook)`.
- Aceite: marcada não enfileira `ActionMailer::MailDeliveryJob`; não marcada enfileira.
- Check: lint; spec em B3.

**B3 · spec · `$R/spec/connecta/scope_notification_delivery_spec.rb` (novo)** (≈15 min) — depende de B1b, B2
- Execução real: `create(:notification, ...)` enfileira; `payload = JSON.parse(job_hash.except(:job, :args, :queue, :priority, :at).to_json)`;
  mudar estado; `ActiveJob::Base.execute(payload)`. Push: `allow(WebPush).to receive(:payload_send)` (padrão
  `$R/spec/services/notification/push_notification_service_spec.rb:13`); email: `with_modified_env SMTP_ADDRESS: 'smtp.example.test'` + `ActionMailer::Base.deliveries`.
- Casos: 1. positivo: push 1×, 1 email, hash com `'connecta_scope'` `epoch: 1`. 2. revoga grant → 0/0. 3. transferência `org_b` e
  `transferred_out` → 0/0. 4. epoch 1→2 com grants → 0/0. 5. chave removida (legado) → 0/0. 6. `user_id` de B no contexto → 0/0.
  7. controle `conv_control` sem contexto → envia e enfileira `MailDeliveryJob`. 8. retry: `job = ActiveJob::Base.deserialize(payload)`,
  epoch→2, `job.serialize['connecta_scope']['epoch'] == 1`, `job.enqueue` gera hash com epoch 1; executá-lo → 0/0. 9. marcado autorizado não enfileira `MailDeliveryJob`.
- Check: spec com `spec/connecta/scope_notification_delivery_spec.rb spec/connecta/scope_notifications_spec.rb`.

**Check B (sem Juiz):** B1a–B3 verdes; lint dos 5 arquivos; casos 2–6 e 8 com 0 `WebPush.payload_send` e 0 entregas.

### Bloco M — RF4 email pendente no ponto final (R3)

**M1 · código · guard `before_deliver` do mailer** (≈15 min) — depende de B1b · ‖ B3
- Criar `$R/app/services/connecta/scope/mail_delivery_guard.rb` (`private def connecta_scope_mail_guard!`):
  - `return unless @conversation.is_a?(Conversation) && Projection.marked?(@conversation.inbox_id)` (sem `@conversation` não houve `mail` → `NullMail`).
  - `ctx = DeliveryContext.take(DeliveryContext::MAILER)`; `n = ctx.is_a?(Hash) ? Notification.find_by(id: ctx['notification_id']) : nil`.
  - `throw :abort unless n && n.user_id == @agent&.id && n.primary_actor_id == @conversation.id && Array(message.to) == [n.user.email] && DeliveryContext.notification_deliverable?(ctx, n)`.
- `installer.rb:28-31`: `AgentNotifications::ConversationNotificationsMailer.include(Connecta::Scope::MailDeliveryGuard)` e
  `.before_deliver(:connecta_scope_mail_guard!)` (mesmo símbolo não duplica ao reinstalar). Sem arg nativo, tabela ou core alterado; cobre ações OSS e SLA.
- Check: lint; spec em M2.

**M2 · spec · `$R/spec/connecta/scope_mail_delivery_pending_spec.rb` (novo)** (≈15 min) — depende de M1
- Cabeçalho como A3; `with_modified_env SMTP_ADDRESS: 'smtp.example.test'`; `ActionMailer::Base.deliveries.clear` no `before`.
- Job nativo real (pendente de antes da instalação): `AgentNotifications::ConversationNotificationsMailer.with(account:).conversation_assignment(conv_a, agent_a, nil).deliver_later`
  → hash `ActionMailer::MailDeliveryJob` → JSON round-trip como B3.
- Casos: 1. autorizado → revoga grant → `ActiveJob::Base.execute` → 0 entregas. 2. idem transferência `org_b`. 3. idem epoch 1→2.
  4. sem mudar estado → 0 (legado marcado sem contexto falha fechado). 5. ponto final: `n = create(:notification, user: agent_a, account:,
  primary_actor: conv_a, notification_type: :conversation_assignment)`; `ctx = DeliveryContext.for_notification(n)`;
  `DeliveryContext.with(ctx, DeliveryContext::MAILER) { ...deliver_now }` → 1; após epoch→2 → 0; `ctx.merge('user_id' => agent_b.id)` → 0.
  6. controle `conv_control` com membro sem grant → `deliver_later` executado → 1. 7. `expect(a_request(:any, /.*/)).not_to have_been_made`.
- Check: spec com `spec/connecta/scope_mail_delivery_pending_spec.rb spec/connecta/scope_notification_delivery_spec.rb`.

**Check M (sem Juiz):** M1–M2 verdes; lint dos 2 arquivos; casos 1–4 e negativos do 5 com `deliveries` vazio.

### Bloco C — RF5 socket: conversa, menção e notificação

**C1 · código · `DeliveryCheck`** (≈15 min) — depende de B1a
- Criar `$R/app/services/connecta/scope/delivery_check.rb` (`module_function`; um método privado por `kind` para `Metrics/AbcSize`):
  - `allowed_tokens(ctx, members, data)`: sem `v == 1` → `[]`; `account = Account.find_by(id: ctx['account_id'])` (nil → `[]`, salvo `unbound`):
    - `native`: `[]` se `ctx['inbox_id']` marcado agora ou `ContactInbox.exists?(contact_id: ctx['contact_id'], inbox_id: marked)`; senão `members`.
    - `unbound`: `[]` se `payload_inbox_id(data)` marcado; senão `members`.
    - `notification`: `n = Notification.find_by(id:)`; `[n.user.pubsub_token]` se `DeliveryContext.notification_deliverable?(ctx, n)`.
    - `conversation`: `conv = account.conversations.find_by(id:)` (nil → `[]`); `account.users.where(id: users.map(&:first))` com
      `epoch_current?`, `!Projection.new(u).admin?`, `Gate.new(u).read?(conv, access_path: 'socket_job')`; mais
      `ContactInbox.where(id: contact_inbox_ids, contact_id: conv.contact_id, inbox_id: conv.inbox_id).pluck(:pubsub_token)`.
    - outro `kind` → `[]` (K3 acrescenta os de contato).
  - `payload_inbox_id(data)`: `d = data.with_indifferent_access`; `d[:inbox_id] || d.dig(:conversation, :inbox_id) || d.dig(:notification, :primary_actor, :inbox_id)`.
    Conferir `rg -n "def push_event_data" -A15 $R/app/models/recurring_scheduled_message.rb $R/app/models/scheduled_message.rb`; sem `inbox_id`, resolver por `account_id` + `conversation_id` (display_id).
  - `legacy_allowed?(event_name, data)`: §1.3 (`::Inbox.exists?(id: marked, account_id:)`, `SocketHook::CONTACT_EVENTS`).
- Check: lint; specs em F1/F2.

**C2 · código · guard de execução do `ActionCableBroadcastJob`** (≈10 min) — depende de B1b, C1
- Criar `$R/app/services/connecta/scope/broadcast_job_guard.rb`: `private def connecta_scope_capture` →
  `DeliveryContext.take(self.class.name) || { 'v' => 1, 'kind' => 'unbound' }`; `perform(members, event_name, data)`: com contexto →
  `members = DeliveryCheck.allowed_tokens(ctx, members, data)`, `return if members.empty?`, `super(members, event_name, data)`;
  sem contexto → `return unless DeliveryCheck.legacy_allowed?(event_name, data)`; `super`.
- `$R/app/services/connecta/scope/installer.rb:77-79` (`install_realtime!`): `ActionCableBroadcastJob.prepend(Connecta::Scope::DeliveryBinding)` e depois `.prepend(Connecta::Scope::BroadcastJobGuard)`.
- Aceite: reload (`action_cable_broadcast_job.rb:25-30`) só depois do guard; chamadores diretos = `unbound` → nativo.
- Check: lint; spec com `spec/connecta/scope_socket_spec.rb spec/connecta/scope_team_contact_spec.rb` (verdes, args intactos).

**C3 · código · `SocketHook` anexa contexto em todo broadcast** (≈15 min) — depende de C2
- `$R/app/services/connecta/scope/socket_hook.rb`:
  - `conversation_mentioned` (`:42-48`): `super` final vira `with_socket_conversation(conversation) { super }`.
  - Novos `notification_created`/`notification_updated(event)`: conversa de `event.data[:notification]` não marcada → `super`;
    `return unless Gate.new(n.user).notifiable?(conversa)`; guardar `n` em `NOTIFICATION_KEY` (padrão de `:149-155`) e `super`.
  - `broadcast` (`:78-86`): após a linha 79, `ctx = DeliveryContext.for_socket(account, tokens, event_name, data)`; só o `super` da linha 80
    entra em `DeliveryContext.with(ctx, 'ActionCableBroadcastJob') { super }`.
- `delivery_context.rb`: `for_socket(account, tokens, event_name, data)`: `NOTIFICATION_KEY` + `notification.*` → `for_notification`;
  `CONVERSATION_KEY` marcado → `conversation` (`users = account.users.where(pubsub_token: tokens).pluck(:id)` + `epoch_of`;
  `contact_inbox_ids = ContactInbox.where(pubsub_token: tokens).ids`); senão `native` com `inbox_id: DeliveryCheck.payload_inbox_id(data)` (contato em K3).
- Check: lint dos 2 arquivos; spec com `spec/connecta/scope_socket_spec.rb spec/connecta/scope_notifications_spec.rb`.

**Check C (sem Juiz):** C1–C3 verdes; lint; `git diff --stat` vazio nas specs aprovadas.

### Bloco K — RF5 contato com classificação explícita (R1)

**K1 · código · Gate por registro de escopo** (≈10 min) — independente de C
- `$R/app/services/connecta/scope/gate.rb:37-42`: extrair privado `scope_allowed?(scope, inbox_id, action)` com o corpo atual (linhas 39 e 41);
  `agent_allowed?` chama `scope_allowed?(ConversationScope.find_by(conversation_id: conversation.id), conversation.inbox_id, action)`.
- Novo público `scope_readable?(scope)` → `!@projection.admin? && scope_allowed?(scope, scope.inbox_id, :read)` (sem auditoria).
- Check: spec com `spec/connecta/scope_policy_query_spec.rb spec/connecta/scope_notifications_spec.rb`.

**K2 · código · classificação pré-destroy em chave própria** (≈15 min) — depende de B1a
- `$R/app/services/connecta/scope/contact_lifecycle_hook.rb`: nova `CONTACT_DELIVERY_KEY = :connecta_scope_contact_delivery` (hash
  `contact_id => entrada`); `CONTACT_SNAPSHOT_KEY` fica **idêntico** (`scope_team_contact_spec.rb:258,307`).
  - Linha 28 (não marcado): também `store_contact_delivery('marked' => false)`.
  - Linha 33 (conta ausente): antes do `return`, `store_contact_delivery('marked' => true, 'users' => [], 'scope_ids' => [])` (fecha).
  - Linhas 36-37: `readers = members.select { ... }`; `tokens = readers.map(&:pubsub_token)`; `store_contact_delivery('marked' => true,
    'users' => readers.map { |u| [u.id, DeliveryContext.epoch_of(u.id)] }, 'scope_ids' => ConversationScope.where(contact_id: id, inbox_id: marked_ids).ids)`.
  - `store_contact_delivery(entry)`: `state[CONTACT_DELIVERY_KEY] = (state[CONTACT_DELIVERY_KEY] || {}).merge(id => entry.merge('account_id' => account_id))`.
  - `ensure` (linha 18): também remove a entrada `id` se `!destroyed?`.
- Só ids, epoch e flag; nenhum dado pessoal.
- Check: lint; spec com `spec/connecta/scope_team_contact_spec.rb` (inalterada, verde).

**K3 · código · contexto de contato no socket + execução** (≈15 min) — depende de C3, K1, K2
- `delivery_context.rb#for_socket`, ramo `CONTACT_EVENTS` antes do `native` genérico:
  - `contact.deleted`: consome (apaga) `CONTACT_DELIVERY_KEY[contact_id]` se `account_id` bate. `marked` true → `contact_deleted`
    (`users`, `scope_ids`); false → `native` com `contact_id`; sem entrada → `contact_ambiguous` se a conta tem inbox marcada, senão `native`.
  - demais: `ContactVisibility.linked?` vivo → `contact` com `users` dos `tokens`; senão `native` com `contact_id`.
- `delivery_check.rb#allowed_tokens`: ramos `contact` e `contact_deleted` (§1.2; tokens de `account.users.where(id:)`); `contact_ambiguous` → `[]`.
- `socket_hook.rb#contact_scoped_tokens` (`:89-101`) não muda (args iguais aos de hoje).
- Check: lint dos 2 arquivos; spec com `spec/connecta/scope_team_contact_spec.rb spec/connecta/scope_socket_spec.rb`.

**Check K (sem Juiz):** K1–K3 verdes; lint; specs aprovadas sem diff.

### Bloco E — admin metadata revalidado (R2)

**E1 · código · contexto e guard do `AdminMetadataBroadcastJob`** (≈15 min) — depende de K3 (mesmo `socket_hook.rb`)
- `$R/app/services/connecta/scope/admin_metadata_broadcast_job.rb:3-10`: `prepend Connecta::Scope::DeliveryBinding`;
  `private def connecta_scope_capture` → `DeliveryContext.take(self.class.name)`; `perform(_tokens, event_name, data)` envia só a
  `current_admin_tokens`: contexto `admin_metadata` v1 (senão `[]`); por `[id, role, epoch]`: `user = account.users.find_by(id:)`,
  `DeliveryContext.epoch_same?`, `role == 'native' ? account.administrators.exists?(id:) : role == 'nominal' && Projection.new(user).admin?`; token atual.
- `socket_hook.rb:111-115`: `socket_admin_tokens` vira `socket_admins(account)` → `[[user, 'native'|'nominal']]` (mesma ordem, `uniq` por id).
- `socket_hook.rb:84-85`: extrair `enqueue_admin_metadata(account, conversation, event_name, data)`; ctx
  `{'v'=>1,'kind'=>'admin_metadata','account_id','admins'=>[[id, role, epoch_of]]}`;
  `DeliveryContext.with(ctx, AdminMetadataBroadcastJob.name) { perform_later(mesmos_tokens_de_hoje, event_name, payload) }`.
- Conteúdo: a exclusão de admin nominal na execução está em C1/K3; quem virou admin depois do enqueue perde o conteúdo e não entra no job de metadados.
- Check: lint dos 2 arquivos; spec com `spec/connecta/scope_socket_spec.rb` (args intactos, verde).

### Bloco F — specs de socket pendente

Comum: cabeçalho como A3; disparar `ActionCableListener.instance`, pegar o job, JSON round-trip como B3, mudar estado,
`ActiveJob::Base.execute(payload)`; observar com `allow(ActionCable.server).to receive(:broadcast)` (sem rede). Legado real =
`ActiveJob::Core.instance_method(:serialize).bind_call(ActionCableBroadcastJob.new(tokens, event, payload))` (serialização nativa sem binding) + JSON round-trip.

**F1 · spec · `$R/spec/connecta/scope_socket_pending_spec.rb` (novo)** (≈15 min) — depende de C3
- 1. `message.created` em `conv_a`: positivo A e manager_a; revoga grant de A → só manager_a. 2. `conversation.updated` + transferência
  `org_b` → A não recebe; sem destinatários `prepare_broadcast_data` não roda. 3. epoch 1→2 com grant → A não. 4. `conversation.mentioned`
  a A + `revoked_locally_at` → nada. 5. `notification.created` de `conv_a`: positivo; revogado → nada. 6. ordinário→nominal: enfileira
  `message.created`, dá `admin_nominal` a A, executa → A sem payload. 7. retry: desserializa, epoch→2, `job.enqueue` → epoch 1; executa →
  A não. 8. `conv_control` sem grant → A recebe (`native`); `ActionCableBroadcastJob.perform_later([agent_a.pubsub_token], 'account.enrichment_completed', { account_id: })` → recebe (`unbound`).
  9. contato do widget recebe `message.created` público.
- Check: spec com `spec/connecta/scope_socket_pending_spec.rb spec/connecta/scope_socket_spec.rb`.

**F2 · spec · `$R/spec/connecta/scope_socket_contact_pending_spec.rb` (novo, R1)** (≈15 min) — depende de K3
- 1. legado real de `contact.deleted` (tokens `["account_<id>"]`, payload `contact_a.push_event_data.merge(account_id:)`) serializado
  **antes** → `contact_a.destroy!` + `ContactInbox.where(contact_id:).delete_all` → executa → 0 broadcasts. 2. legado `contact.updated`
  de `contact_control` em conta marcada → 0 (limite §1.3). 3. legado `message.created` de `conv_control` → nativo. 4. legado
  `contact.deleted` em outra conta sem inbox marcada → nativo. 5. novo não marcado: destroy real de contato só em `control_inbox` → hash
  com `kind: 'native'` e `contact_id`; executa → `account_<id>` recebe. 6. novo marcado (padrão `scope_team_contact_spec.rb:241-247`),
  vínculos apagados: positivo A e manager_a; revogação/epoch→2 → nada; nunca `account_<id>`. 7. listener direto sem destroy em conta
  marcada → `contact_ambiguous` → 0. 8. `contact.updated` de `contact_a` + revogação → nada.
- Check: spec com `spec/connecta/scope_socket_contact_pending_spec.rb spec/connecta/scope_team_contact_spec.rb`.

**F3 · spec · `$R/spec/connecta/scope_admin_metadata_pending_spec.rb` (novo, R2)** (≈15 min) — depende de E1
- `let!(:native_admin) { create(:user, account:, role: :administrator) }` (como `scope_socket_spec.rb:18`); `message.created` em `conv_a`.
- 1. positivo: `admin_nominal` e `native_admin` recebem só `{id, conversation_id, account_id}`. 2. grant `admin_nominal` removido → não.
  3. epoch→2 → não. 4. `revoked_locally_at` → não. 5. `AccountUser` do `native_admin` → `role: :agent` → não. 6. A vira `admin_nominal`
  após o enqueue → não recebe metadados (sem destinatário novo). 7. payload sem `'connecta_scope'` → nada.
- Check: spec com `spec/connecta/scope_admin_metadata_pending_spec.rb spec/connecta/scope_socket_spec.rb`.

**Check F (sem Juiz):** F1–F3 verdes; lint dos 3 arquivos; nenhum broadcast a token revogado/stale nos negativos.

### Bloco D — fechamento (sem código)

- D1 · regressão G0: spec com todos os `spec/connecta/scope_*_spec.rb`, `spec/connecta/attachment_*_spec.rb` e `spec/connecta/agent_bot_delivery_spec.rb` (2–3 execuções se passar de 300 s).
- D2 · lint de `app/services/connecta/scope spec/connecta` (formato JSON da evidência 29).
- D3 · evidência nova em `.context/evidence/g0/` (próximo número): logs, contagens, mapa caso → linha de spec e o limite de §1.3.
  Changelog/PROJECT_STATE ficam com o orquestrador.
- **Check D:** D1–D3. Depois o orquestrador junta RF1–RF6 e chama o **Gate G0 (único Juiz)**.

## 3. Rollback

Tudo é prepend/callback instalado por teste: remover as linhas do `installer.rb` do passo e os arquivos novos. `gate.rb` (K1),
`contact_lifecycle_hook.rb` (K2), `socket_hook.rb` (C3/K3/E1) e `admin_metadata_broadcast_job.rb` (E1) voltam pelo diff do passo.

## 4. Riscos

| Risco | Mitigação |
|---|---|
| Contexto de thread no job errado | `take` por nome da classe e uso único; `with` envolve um `perform_later`; `ensure` restaura (F1 caso 8). |
| Retry recapturar estado novo | `@connecta_scope_captured` restaurado no `deserialize` (B3 caso 8, F1 caso 7). |
| Legado de contato em conta marcada perdido | Aceito e documentado (§1.3): só aviso de UI; não é residual de privacidade. |
| `AccessAudit` por destinatário no job | Mesmo custo do listener (`socket_hook.rb:71`); `access_path: 'socket_job'`. |
| Janela guard → broadcast/SMTP | Mesmo processo, sem fila; email checa no `before_deliver`. Revogação completa (T3.2) fora deste plano. |

## Apêndice — alternativas descartadas

- Wrapper com contexto como 1º argumento: quebraria as specs aprovadas que leem `args`.
- Captura em `serialize` (rev. 1): dependia do adaptador serializar dentro do bloco; `enqueue` é explícito e síncrono.
- Novas chaves no snapshot atual (rev. 1 C4) ou tombstone/tabela: quebra `scope_team_contact_spec.rb:258,307` / vetado.
- Binding no `MailDeliveryJob`: desnecessário; marcado novo não usa fila e o legado falha fechado no `before_deliver`.
- Apagar notificações na revogação: vetado; ocultar cobre lista, contagem e ação.
