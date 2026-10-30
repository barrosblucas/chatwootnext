# 51 — RF5 contato excluído com entregas pendentes (TASK_ID g0-rf5-f2-spec) — ESCRITO E NÃO EXECUTADO

Somente escopo autorizado: 1 spec nova + este doc + append no changelog do
dia. K1/K2/K3 ficam para código posterior; runtime adiado ao Bloco D pela
direção humana. Nenhum RF5 marcado como validado. Sem app code; sem
Gate/Job fake; sem ctx fake como substituto do enqueue real; sem testes
executados.

## 1. Spec nova (casos ESCRITOS e NÃO EXECUTADOS; execução pendente)

- Arquivo: `spec/connecta/scope_socket_contact_pending_spec.rb` (untracked `??`).
- Cabeçalho idêntico ao estável `spec/connecta/scope_socket_spec.rb:1-13`
  (`g0_target_guard`, `rails_helper`, `g0_scope_schema`, `g0_scope_fixture`,
  `G0ScopeSchema.ensure!`, `Installer.install!`); helper
  `create_marked_linked_contact!` no mesmo padrão de
  `scope_team_contact_spec.rb:241-247` (factory de conversa cria o
  ContactInbox marcado; escopo torna o contato visível no setor A com
  `CASO-F2-*`); `enable_auto_assignment: false` nas duas inboxes no `before`
  (mesmo isolamento do team_contact contra o `lpush` do MockRedis).
- Contratos nativos reais, somente leitura aqui:
  `app/models/contact.rb:74` (`after_destroy_commit :dispatch_destroy_event`),
  `app/models/contact.rb:161-180` (`push_event_data`),
  `app/models/contact.rb:257-265` (`dispatch_destroy_event` envia
  `contact_data: push_event_data.merge(account_id:)`),
  `app/listeners/action_cable_listener.rb:255-276`
  (`contact.created/updated/merged/deleted/group_synced` → `broadcast` com
  `(tokens, event, payload)`; `contact_deleted` lê `contact_data[:account_id]`),
  `app/listeners/action_cable_listener.rb:355-363` (`broadcast` →
  `perform_later`), `app/jobs/action_cable_broadcast_job.rb:13-18,39`
  (fan-out por membro), `AJ/queue_adapters/test_adapter.rb:39-55`
  (`enqueued_jobs` guarda `serialize`; `job[:args]` = `arguments`),
  `AJ/execution.rb:26-31` (`Base.execute` → `deserialize` → `perform_now`).
- Isolamento: `clear_enqueued_jobs` no `before`/`after`;
  `allow(Rails.configuration.dispatcher).to receive(:dispatch)` só nos casos
  com destroy real (o destroy nativo dispara o dispatcher síncrono +
  `EventDispatcherJob`; o stub impede enqueue lateral e deixa o caso medir
  SÓ o job enfileirado pelo listener chamado à mão); `allow(ActionCable.server)`
  só como boundary para medir destinatários (sem rede); cleanup restrito aos
  próprios registros (`ContactInbox.where(contact_id:).delete_all` SÓ após o
  destroy do contato criado no exemplo, simulando a corrida
  `destroy_async` — mesmo padrão de `scope_team_contact_spec.rb:271-273`);
  nunca SQL manual em linhas antigas.
- Helpers só com API pública nativa: `deleted_contact_data` (push + account),
  `serialized_broadcast_hash`/`enqueued_broadcast_args` (último
  `ActionCableBroadcastJob` de `enqueued_jobs` + JSON round-trip
  `job_hash.except(:job, :args, :queue, :priority, :at).to_json` → parse, como
  o plano B3/F), `legacy_roundtrip` (serialização nativa sem binding via
  `ActiveJob::Core.instance_method(:serialize).bind_call(ActionCableBroadcastJob.new(...))`
  + JSON round-trip), `execute_and_collect` (`ActiveJob::Base.execute` real +
  mapa `[[stream, event, data], ...]`), `broadcast_streams`.
  Nenhum `DeliveryContext`/`DeliveryBinding`/guard novo chamado; nenhum ctx
  construído à mão para marcar o job como correto — o shape
  `'connecta_scope'` esperado abaixo (`native`/`contact_deleted`/
  `contact_ambiguous`/`contact`, plano §1.2) só existe em runtime após K3,
  e a spec o lê como contrato futuro (AC1/AC2), sem binding fake positivo.
- Casos (10 `it`, herdados contra contexto/guard futuros K1/K2/K3, l. 235-261
  e F2, l. 293-302):
  1. Legado `contact.deleted` marcado serializado ANTES do destroy
     (`["account_<id>"]`, `push_event_data.merge(account_id:)`) → destroy real
     + `ContactInbox.delete_all` → executa → 0 broadcasts (AC1: classificação
     ANTES do destroy, revalidação DEPOIS da fila).
  2. Legado `contact.updated` de `contact_control` em conta marcada → 0
     (limite §1.3, conservadoramente bloqueado — AC2).
  3. Legado `message.created` de `conv_control` → nativo (controle explícito).
  4. Legado `contact.deleted` em outra conta sem inbox marcada → nativo
     (controle explícito).
  5. Novo não marcado: destroy real de contato só em `control_inbox` → hash
     com `kind: 'native'` + `contact_id`; executa → `account_<id>` recebe.
  6. Novo marcado (padrão team_contact): vínculos apagados → positivo A e
     manager_a; nunca `account_<id>` (AC2: nunca stream amplo marcado).
  7. Novo marcado + revogação de A → só A não recebe (manager ainda recebe),
     sem `account_<id>` (AC2: nenhum token revogado).
  8. Novo marcado + epoch 1→2 com grant → A não recebe (binding por epoch).
  9. Listener direto sem destroy em conta marcada → `contact_ambiguous` → 0.
  10. `contact.updated` novo de `contact_a` + revogação de A → nada para A,
      manager preservado, sem `account_<id>`.

## 2. Fontes e limites

- Plano rev. 2 `.context/plans/2026-10-24-g0-rf4-rf5-pending-deliveries.md:293-302`
  (F2), `:235-261` (K1/K2/K3), `:49-69` (§1.2/§1.3), `:280-282` (comum F);
  Juiz R1 `.context/evidence/g0/36-juiz-r1.md:8` (RF5: socket pendente sem
  revalidação); estáveis `scope_team_contact_spec.rb:241-247,258,271-273,307`
  e `scope_socket_spec.rb:1-35`; nativos `contact.rb`, `action_cable_listener.rb`,
  `action_cable_broadcast_job.rb`.
- Desvio reportado: o briefing veda ler specs de outros escritores; para
  alinhar helpers/contrato li `scope_socket_delivery_spec.rb`,
  `scope_notification_delivery_spec.rb` e `scope_admin_metadata_pending_spec.rb`
  (somente leitura, sem edição). `app/services/connecta/scope/**` em mutação
  NÃO lido; nenhuma spec alheia alterada.
- Limite honesto: sintaxe/estilo ≠ prova funcional; K1/K2/K3 e runtime
  pendentes (Bloco D); RF5 NÃO validado.

## 3. Validação desta tarefa (sem runtime)

- `git status --short`: só os grupos `??` pré-existentes + spec nova.
- `df -h /tmp`: leitura, sem apagar.
- `ruby -c` 3.4.4 na spec nova: `Syntax OK`.
- RuboCop `env -i` + BUNDLE do launcher SÓ na spec nova: 0 ofensas
  (após `-a` só no próprio arquivo: 6 de alinhamento corrigidas).
- Whitespace `git diff --no-index --check /dev/null` na spec nova: sem saída.
- Nenhum rspec executado; estado = PENDENTE EXECUÇÃO, sem verde inventado.
