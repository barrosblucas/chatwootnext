# 44 — RF4 email ponto final (TASK_ID g0-rf4-m2-spec) — ESCRITO E NÃO EXECUTADO

Somente escopo autorizado: 1 spec nova + este doc + append no changelog do dia.
M1 fica para código posterior; runtime adiado ao Bloco D pela direção humana
("primeiro executa tudo, depois testa"). Nenhum RF4 marcado como validado.
Sem Gate/before_deliver/perform stubado; sem helpers novos da infra chamados;
sem jobs reais executados aqui; sem testes executados; sem SMTP externo.

## 1. Spec nova (casos ESCRITOS e NÃO EXECUTADOS; execução pendente)

- Arquivo: `spec/connecta/scope_mailer_delivery_spec.rb` (untracked `??`; nome
  segue o briefing; plano l. 180 previa `scope_mail_delivery_pending_spec.rb` —
  desvio fiel, mesmo conteúdo M2, sem renomear o plano).
- Cabeçalho idêntico ao estável `spec/connecta/scope_notifications_spec.rb:1-13`
  (`g0_target_guard`, `rails_helper`, `g0_scope_schema`, `g0_scope_fixture`,
  `G0ScopeSchema.ensure!`, `Installer.install!`); factory nativa
  `create(:notification, user:, account:, primary_actor: conv)` (`spec/factories/notifications.rb:4-11`).
- Contratos nativos reais, somente leitura aqui:
  `app/models/notification.rb:183-191` (`after_create_commit` enfileira
  `PushNotificationJob`/`EmailNotificationJob` nativos),
  `app/jobs/notification/email_notification_job.rb:1-10` (pula `read_at`,
  roda `Notification::EmailNotificationService`),
  `app/services/notification/email_notification_service.rb:20-24`
  (`deliver_later` → `MailDeliveryJob`),
  `app/mailers/agent_notifications/conversation_notifications_mailer.rb:14-22`
  (`conversation_assignment`, `@conversation`/`@agent`, `send_mail_with_liquid`
  com `to: @agent.email`),
  `app/mailers/application_mailer.rb:25-27` (`SMTP_ADDRESS` presente libera `mail`),
  `.bundle/actionmailer-7.1.5.2/lib/action_mailer/mail_delivery_job.rb:21-29`
  (perform `with(params)` → ação → `send(delivery_method)`),
  `message_delivery.rb:123-129` + `callbacks.rb:9,15-17` (`deliver_now` roda
  `before_deliver` com `to`/`subject` prontos),
  `AJ/queue_adapters/test_adapter.rb:39-55` (`enqueued_jobs` guarda `serialize`),
  `AJ/execution.rb:26-31` (`Base.execute` → `deserialize` → `perform_now`).
- Isolamento: `clear_enqueued_jobs` + `ActionMailer::Base.deliveries.clear` no
  `before`/`after`; `with_modified_env SMTP_ADDRESS: 'smtp.example.test'` (sem
  VAPID aqui — M2 é só email); tipo `conversation_assignment` (mailer não
  consulta `OnlineStatusTracker`, então 0 email nos negativos não passa só por
  usuário online). Sem Vite; `Mail.assets` não precisou de stub (registrado aqui).
- Helpers só com API pública nativa: `mailer_job_hashes` (conta
  `MailDeliveryJob`), `payload_for` (round-trip
  `job_hash.except(:job, :args, :queue, :priority, :at).to_json` → `JSON.parse`,
  como B3), `legacy_mailer_payload_for` (mailer real
  `with(account:).conversation_assignment(conv, agent, nil).deliver_later` →
  exige 1 `MailDeliveryJob` → payload; atua como job serializado ANTES dos
  guards M1), `email_job_hashes_for` (filtra `EmailNotificationJob` por
  `ActiveJob::Arguments.deserialize(job[:args])` com `id` da notification).
  Nenhum `DeliveryContext`/`MailDeliveryGuard` novo chamado (M1 pendente).
- Positivo eleito sem `should_notify?` falso: contato/assinante/preferences
  nativos (`inbox_member` do fixture + `selected_email_flags` com todas as
  chaves `Notification::NOTIFICATION_TYPES` + `confirmed_at` presente) para o
  caminho `deliver_now` real sob teste.
- Casos (7 `it`,erdados contra o guard futuro M1, l. 171-178):
  1. Legado marcado pendente + revoga grant de A → `Base.execute` dá 0
     (fail-closed, grant removido).
  2. Legado marcado + transferência scope (`org_b` + `transferred_out`, AR sem
     LocalTransaction RF6) → 0.
  3. Legado marcado + epoch 1→2 COM GRANT AINDA ATIVO (`count > 0` antes e
     depois) → 0 (Gate current sozinho não basta).
  4. Legado marcado sem mudar estado → 0 (marcado sem contexto falha fechado,
     §1.3; legado fail-closed mesmo quando grant permanece).
  5. Fluxo novo marcado: `execute(email_hash)` autorizado entrega 1 via
     `deliver_now` sem `MailDeliveryJob` (B2: marcada não nasce job
     desprotegido); hash com `'connecta_scope'` `epoch: 1`; `user_id` de B no
     ctx → 0; epoch→2 → 0 (mesmo `it`, sem explodir a suite).
  6. Controle `conv_control` não marcado com membro sem grant →
     `execute(payload)` entrega 1 + `a_request(:any, /.*/)` sem rede
     (unmarked nativo preservado).
  7. Barreira final: `define_method(:connecta_scope_test_race_hook!)` +
     `before_deliver(..., prepend: true)` revoga epoch 1→2 DURANTE o Mailer
     (antes do guard de produção M1) → `execute(email_hash)` dá 0 com grant
     ainda ativo; `skip_callback(..., raise: false)` no `ensure` restaura o
     mailer; sem mexer em file core; sem stubar Gate/`before_deliver` de
     produção/`perform`.
- Nenhum caso marca RF4 como validado; M1 e runtime pendentes (Bloco D).
  Sem M2 duplicando B3: B3 cobre o Parent (`Push`/`EmailNotificationJob`); este
  arquivo cobre o legado `MailDeliveryJob` serializado e a releitura final no
  endpoint `before_deliver` + race determinístico.

## 2. Checagens reais desta tarefa (1 alvo, sem runtime)

Comandos (caminhos absolutos, receita `scripts/connecta/g0_test_env.sh:47-49` + `gotchas.md:43`):

```sh
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c spec/connecta/scope_mailer_delivery_spec.rb
env -i PATH=.../ruby/3.4.4/bin:... BUNDLE_GEMFILE=... BUNDLE_PATH=... BUNDLE_FROZEN=true bundle exec rubocop <nova spec>
git diff --no-index --check /dev/null <nova spec>
git diff --check
git status --short
df -h /tmp
```

- Resultado factual: `ruby -c` 3.4.4 `Syntax OK`, EXIT 0; RuboCop check-only
  `env -i` + BUNDLE do launcher SÓ na nova spec → **1 arquivo, 0 ofensas**,
  EXIT 0 (antes: 4 — `MultilineMethodCallIndentation` no helper
  `legacy_mailer_payload_for`, `ArgumentAlignment` + `HashAlignment` no
  `update!(org_unit:, state:)`; correção mínima só no arquivo novo: 1 linha
  no `legacy_mailer_payload_for` (142 chars, dentro do `Max: 150`) + 1 linha
  no `update!` (128 chars)).
- Whitespace: `git diff --no-index --check /dev/null <nova spec>` sem saída
  (exit 1 = há diff contra /dev/null, semântica de `29-regressao-lint.md` §6;
  só a saída conta).
- `git diff --check` (rastreado): limpo. `git status --short`: só os 7 grupos
  `??` pré-existentes (`.context/`, `app/services/connecta/{scope,transfer}/`,
  `scripts/`, `spec/{connecta,requests/connecta,support/connecta}/`; nenhum
  rastreado modificado). `df -h /tmp` 7.6G/5.1G/67% (leitura, sem apagar).
- Nenhum spec/teste funcional executado (`rspec` NÃO rodado); nenhum
  build/lint global; nenhum SQL manual/banco/migração/teardown; sem
  servidor/produção/QR/commit; PROJECT_STATE não editado (fora de escopo).

## 3. Fontes e limites

- Plano rev. 2 `.context/plans/2026-10-24-g0-rf4-rf5-pending-deliveries.md:169-190`
  (M1 guard + M2 casos); fonte M2/l. 180-190 prevalece, com nome do arquivo
  vindo do briefing.
- Juiz R1 `.context/evidence/g0/36-juiz-r1.md:7` (RF4: Gate só na criação;
  lista/contagem e push/email pendentes sem revalidação).
- Estáveis, só leitura: `spec/connecta/scope_notification_delivery_spec.rb`
  (padrões `enqueued_jobs`/JSON/`Base.execute`; B3 NÃO duplicado),
  `spec/connecta/scope_notifications_spec.rb` (fixture/Installer),
  `spec/connecta/scope_notification_existing_spec.rb` (padrão `with_modified_env`
  + callbacks limpos), `app/models/notification.rb`, jobs push/email nativos,
  `email_notification_service.rb`, mailer + template
  `conversation_assignment.liquid`, `spec/connecta/support/g0_scope_fixture.rb`,
  factories notification, `active_support/callbacks.rb:774-785`
  (`prepend: true` real), `spec_helper.rb:16` (`with_modified_env`),
  `spec_helper.rb:1` (`webmock/rspec`, `a_request` sem rede).
- RF2 (`scope_contact_fields_spec.rb`, outro Coder) e RF1/RF3/RF5/RF6 NÃO
  tocados; helpers novos/installer em mutação NÃO lidos; `NativeMailer`/
  `NativeActionMailer`/`EmailNotificationJob` nativos só leitura.
- Limite honesto: sintaxe/estilo ≠ prova funcional; sem runtime, sem Gate fake,
  sem RF4 validado; helpers de código e execução real pendentes (Bloco D).
  Positivo usa `should_notify?` verdadeiro via preferences/confirmados nativos
  (sem 0 falso); `Mail.assets` sem stub (Vite fora do caminho testado);
  `deliveries.clear` por caso impede vazamento entre exemplos.
