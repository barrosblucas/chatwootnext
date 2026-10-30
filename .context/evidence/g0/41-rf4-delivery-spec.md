# 41 — RF4 entrega pendente push/email (TASK_ID g0-rf4-b3-spec) — ESCRITO E NÃO EXECUTADO

Somente escopo autorizado: 1 spec nova + este doc + append no changelog do dia.
B1b/B2 ficam para código posterior; runtime adiado ao Bloco D pela direção humana
("primeiro executa tudo, depois testa"). Nenhum RF4 marcado como validado.
Sem Gate/finder/controller stubado; sem helpers novos da infra; sem jobs reais
executados aqui; sem testes executados.

## 1. Spec nova (casos ESCRITOS e NÃO EXECUTADOS; execução pendente)

- Arquivo: `spec/connecta/scope_notification_delivery_spec.rb` (untracked `??`).
- Cabeçalho idêntico ao estável `spec/connecta/scope_notifications_spec.rb:1-13`
  (`g0_target_guard`, `rails_helper`, `g0_scope_schema`, `g0_scope_fixture`,
  `G0ScopeSchema.ensure!`, `Installer.install!`); factory nativa
  `create(:notification, user:, account:, primary_actor: conv)` (`spec/factories/notifications.rb:4-11`).
- Contratos nativos reais, somente leitura aqui:
  `app/models/notification.rb:58,183-191` (`after_create_commit` enfileira
  `PushNotificationJob`/`EmailNotificationJob` nativos),
  `app/jobs/notification/push_notification_job.rb:1-7` + `email_notification_job.rb:1-10`,
  `AJ/queue_adapters/test_adapter.rb:39-55` (`enqueued_jobs` guarda `serialize`; `job[:args]`
  = `arguments`), `AJ/execution.rb:26-31` (`Base.execute` → `deserialize` → `perform_now`),
  push `push_notification_service.rb:66-69` (`WebPush.payload_send`, padrão
  `spec/services/notification/push_notification_service_spec.rb:13`),
  email `email_notification_service.rb:20-24` (`deliver_later` → `MailDeliveryJob`) +
  `application_mailer.rb:25-27` (`SMTP_ADDRESS` presente libera `mail`),
  subscription `spec/factories/notification_subscriptions.rb:1-18` (`browser_push`).
- Isolamento: `clear_enqueued_jobs` + `ActionMailer::Base.deliveries.clear` no `before`/`after`;
  `allow(WebPush).to receive(:payload_send)` (sem IO externo; FCM/Hub não configurados);
  `with_modified_env SMTP_ADDRESS: 'smtp.example.test'` + `VAPID_PUBLIC_KEY: 'test'`
  (VAPID via ENV em `lib/vapid_service.rb:17-18`, sem rede); tipo
  `conversation_assignment` (mailer não consulta `OnlineStatusTracker`, então 0 email
  nos negativos não passa só por usuário online); `browser_push` real para A
  (fake boundary válida: 0 push nos negativos não passa só por falta de subscription).
- Helpers só com API pública nativa: `delivery_job_hashes_for` (filtra
  `Push`/`EmailNotificationJob` por `ActiveJob::Arguments.deserialize(job[:args])`
  com `id` da notification), `payload_for` (round-trip
  `job_hash.except(:job, :args, :queue, :priority, :at).to_json` → `JSON.parse`,
  como o plano), `mailer_job_hashes` (conta `MailDeliveryJob` enfileirado).
  Nenhum `DeliveryContext`/`DeliveryBinding`/guard novo chamado.
- Casos (10 `it`,erdados contra binding/guard futuros B1b/B2, l. 138-155):
  1. Positivo marcado autorizado: push 1×, 1 email, hash com `'connecta_scope'`
     `epoch: 1` (`v/kind/account/conversation/notification/user`), `MailDeliveryJob` vazio
     (prova que o guard não bloqueia tudo — AC2).
  2. Revoga grant de A após serialize → `Base.execute` push/email dá 0/0, sem `MailDeliveryJob`.
  3. Transferência por scope (`org_b` + `transferred_out`, AR sem LocalTransaction RF6)
     → 0/0.
  4. Epoch 1→2 COM GRANT AINDA ATIVO (`UserGrant.count > 0` antes e depois) → 0/0
     (Gate current sozinho não basta; mesma exigência do plano l. 132).
  5. Legado sem chave em marcada → 0/0 (falha fechada §1.3); sem chave em controle
     → push 1× nativo (mesmo `it`, sem explodir a suite).
  6. `user_id` de B no contexto de A → 0/0 (contexto de outro usuário não entrega).
  7. Controle `conv_control` sem contexto → push 1× + `MailDeliveryJob` enfileirado
     (nativo preservado).
  8. Retry não recaptura versão nova: `deserialize(payload)` → epoch→2 →
     `serialize['connecta_scope']['epoch'] == 1` → `enqueue` gera hash com epoch 1 →
     executar dá 0/0 (plano l. 163-164).
  9. Marcado autorizado não enfileira `MailDeliveryJob` desprotegido; `execute(email_hash)`
     entrega 1 via `deliver_now` autorizado (B2: marcada não nasce `MailDeliveryJob`).
  10. Admin nominal jamais notificado de marcada, mesmo com linha existente → 0/0,
      linha intacta (`gate.rb:29` dá `read?` a ele; exclusão explícita §1.2).
- Nenhum caso marca RF4 como validado; B1b/B2 e runtime pendentes (Bloco D).
  Sem M2 final (`MailDeliveryJob` pendente) nem socket RF5 neste arquivo.

## 2. Checagens reais desta tarefa (1 alvo, sem runtime)

Comandos (caminhos absolutos, receita `scripts/connecta/g0_test_env.sh:47-49` + `gotchas.md:43`):

```sh
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c spec/connecta/scope_notification_delivery_spec.rb
env -i PATH=.../ruby/3.4.4/bin:... BUNDLE_GEMFILE=... BUNDLE_PATH=... BUNDLE_FROZEN=true bundle exec rubocop <nova spec>
git diff --no-index --check /dev/null <nova spec>
git diff --check
git status --short
df -h /tmp
```

- Resultado factual: `ruby -c` 3.4.4 `Syntax OK`, EXIT 0; demais saídas na seção
  de validação do relatório (sem `rspec`; sem alegar verde funcional).
- `df -h /tmp` só leitura (sem apagar); PROJECT_STATE não editado (fora de escopo).

## 3. Fontes e limites

- Plano rev. 2 `.context/plans/2026-10-24-g0-rf4-rf5-pending-deliveries.md:124-165`
  (B1a/B1b/B2 contrato + B3 casos); fonte B3/l. 157-165 prevalece.
- Juiz R1 `.context/evidence/g0/36-juiz-r1.md:7` (RF4: Gate só na criação;
  lista/contagem e push/email pendentes sem revalidação).
- Estáveis, só leitura: `spec/connecta/scope_notifications_spec.rb` (padrões
  `enqueued_jobs`/listener), `app/models/notification.rb`, jobs push/email nativos,
  `email_notification_service.rb`, `push_notification_service.rb`,
  `application_mailer.rb`, `lib/vapid_service.rb`,
  `spec/connecta/support/g0_scope_fixture.rb`, factories notification/subscription.
- RF3 (ContactHook/CreateSpec) e installer em mutação NÃO lidos; nenhum helper novo
  da infra chamado; M2 final e socket RF5 fora deste arquivo.
- Limite honesto: sintaxe/estilo ≠ prova funcional; sem runtime, sem Gate fake,
  sem RF4 validado; helpers de código e execução real pendentes (Bloco D).
