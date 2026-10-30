# 49 — RF5 admin metadata pendente (TASK_ID g0-rf5-f3-spec) — ESCRITO E NÃO EXECUTADO

Somente escopo autorizado: 1 spec nova + este doc + fechamento F1 (doc 43) + append
no changelog do dia. E1 fica para código posterior; runtime adiado ao Bloco D pela
direção humana ("primeiro executa tudo, depois testa"). Nenhum RF5 marcado como validado.
Sem app code; sem Gate/Job fake; sem ctx fake como substituto do enqueue real;
sem testes executados.

## 1. Spec nova (casos ESCRITOS e NÃO EXECUTADOS; execução pendente)

- Arquivo: `spec/connecta/scope_admin_metadata_pending_spec.rb` (untracked `??`).
- Cabeçalho idêntico ao estável `spec/connecta/scope_socket_spec.rb:1-13`
  (`g0_target_guard`, `rails_helper`, `g0_scope_schema`, `g0_scope_fixture`,
  `G0ScopeSchema.ensure!`, `Installer.install!`); `let!(:native_admin)` como
  `scope_socket_spec.rb:18` (`create(:user, account:, role: :administrator)`);
  `message.created` em `conv_a` via listener nativo `ActionCableListener.instance`.
- Contratos nativos reais, somente leitura aqui:
  `app/listeners/action_cable_listener.rb:355-363` (`broadcast` → `perform_later`
  com `(tokens, event_name, payload)`),
  `app/jobs/action_cable_broadcast_job.rb:13-18,25-30` (reload + broadcast por membro),
  `AJ/queue_adapters/test_adapter.rb:39-55` (`enqueued_jobs` guarda `serialize`;
  `job[:args]` = `arguments`), `AJ/execution.rb:26-31` (`Base.execute` → `deserialize`
  → `perform_now`), `AJ/core.rb` (`serialize` nativo sem binding no caso legado),
  `app/models/account.rb:129-132` (`administrators` = `account_users.role :administrator`).
- Isolamento: `clear_enqueued_jobs` no `before`/`after`; `allow(ActionCable.server).to
  receive(:broadcast)` só como boundary para medir destinatários e conteúdo (sem rede);
  fixture test-only com `conv_a` marcada e setores A/B da `g0_scope_fixture.rb`.
- Helpers só com API pública nativa: `enqueued_admin_job` (filtra
  `Connecta::Scope::AdminMetadataBroadcastJob` em `enqueued_jobs`),
  `roundtrip`/`enqueue_and_roundtrip` (enqueue pelo listener nativo + JSON round-trip
  `job_hash.except(:job, :args, :queue, :priority, :at).to_json` → `JSON.parse`,
  como o plano B3/F), `broadcasts_by_token` (`ActiveJob::Base.execute` real +
  mapa token → `data`), `metadata_for` (`with_indifferent_access` por usuário).
  Nenhum `DeliveryContext`/`DeliveryBinding`/guard novo chamado; nenhum ctx construído
  à mão para marcar o job como correto.
- Casos (7 `it`, erdados contra contexto/guard futuros E1, l. 266-277 e F3, l. 303-309):
  1. Positivo: `admin_nominal` e `native_admin` recebem só
     `{id, conversation_id, account_id}` (`id` = `scoped_message.id`,
     `conversation_id` = `conv_a.display_id`, `account_id` = `account.id`);
     chaves exatas `account_id/conversation_id/id`, sem `body`/`snippet`/`content` (AC2).
  2. Grant `admin_nominal` removido após serialize → nominal não recebe; nativo válido
     ainda recebe o mesmo trio (compara token individual e conteúdo, sem exigir
     broadcast global 0 — AC1).
  3. Epoch 1→2 COM GRANT AINDA ATIVO → nominal não recebe; nativo válido ainda recebe.
  4. `revoked_locally_at` setado → nominal não recebe; nativo válido ainda recebe.
  5. `AccountUser` do `native_admin` → `role: :agent` (demote nativo real) → nativo não
     recebe; nominal válido ainda recebe o trio.
  6. A vira `admin_nominal` após o enqueue (grant novo em `org_root`) → A não recebe
     novo destino; os dois admins do enqueue ainda recebem (sem novos destinos — AC2).
  7. Payload legado sem `'connecta_scope'` (serialização nativa via
     `ActiveJob::Core#serialize` sem binding + JSON round-trip) → nada entregue (AC1).
- Nenhum caso marca RF5 como validado; E1 e runtime pendentes (Bloco D).
  Sem emissão `contact.deleted` (F2 separada); sem email B3/M2 neste arquivo.

## 2. Checagens reais desta tarefa (2 alvos novos, sem runtime)

Comandos (caminhos absolutos, receita `scripts/connecta/g0_test_env.sh:47-49` + `gotchas.md:43`):

```sh
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c spec/connecta/scope_admin_metadata_pending_spec.rb
env -i PATH=.../ruby/3.4.4/bin:... BUNDLE_GEMFILE=... BUNDLE_PATH=... BUNDLE_FROZEN=true bundle exec rubocop <nova spec>
git diff --no-index --check /dev/null <nova spec>
git diff --check
git status --short
df -h /tmp
```

- Resultado factual: `ruby -c` 3.4.4 `Syntax OK`, EXIT 0; RuboCop check-only `env -i` +
  BUNDLE do launcher só na nova spec → **1 arquivo, 0 ofensas**, EXIT 0, stderr vazio.
  Antes: 3 ofensas (`RSpec/DescribeClass` no describe de string,
  `Lint/RedundantCopDisableDirective` no disable então redundante,
  `Style/SafeNavigation` no helper `metadata_for`); depois: 0, sem tocar helpers
  compartilhados nem outros specs. Correções mínimas só no arquivo novo: describe na
  classe sob teste (`Connecta::Scope::AdminMetadataBroadcastJob`, mantido o disable
  `RSpec/SpecFilePathFormat` exigido pelo nome fixado F3), safe navigation no helper,
  `described_class` no caso legado.
- Whitespace: `git diff --no-index --check /dev/null <nova spec>` sem saída
  (exit 1 = há diff contra /dev/null, semântica de `29-regressao-lint.md` §6; só a saída conta).
- `git diff --check` (rastreado): limpo. `git status --short`: só os 7 grupos `??`
  pré-existentes (`.context/`, `app/services/connecta/{scope,transfer}/`, `scripts/`,
  `spec/{connecta,requests/connecta,support/connecta}/`; nenhum rastreado modificado).
  `df -h /tmp` 7.6G/5.1G/67% (leitura, sem apagar).
- Nenhum spec/teste funcional executado (`rspec` NÃO rodado); nenhum build/lint global;
  nenhum SQL manual/banco/migração/teardown; sem servidor/produção/QR/commit;
  PROJECT_STATE não editado (fora de escopo).

## 3. Fontes e limites

- Plano rev. 2 `.context/plans/2026-10-24-g0-rf4-rf5-pending-deliveries.md:266-277` (E1)
  e `:303-309` (F3); fonte F3/l. 303-309 prevalece para os casos.
- Juiz R1 `.context/evidence/g0/36-juiz-r1.md:8` (RF5: socket pendente sem revalidação;
  admin metadata em `admin_metadata_broadcast_job.rb` + `socket_hook.rb` citado no plano §0).
- Estáveis, só leitura: `spec/connecta/scope_socket_spec.rb` (padrões listener/enqueue),
  `spec/connecta/support/g0_scope_fixture.rb` (setores/controle/grants/epochs),
  `app/listeners/action_cable_listener.rb`, `app/jobs/action_cable_broadcast_job.rb`,
  `app/models/account.rb` (demote via `AccountUser#role`), factories de user/message.
- `app/services/connecta/scope/**` e installer em mutação NÃO lidos; specs de outros
  escritores (`scope_socket_delivery_spec.rb`, M2, RF2/RF3/RF4) NÃO lidas; nenhum helper
  novo da infra chamado; E1 e socket RF5 (F1/F2) fora deste arquivo.
- Limite honesto: sintaxe/estilo ≠ prova funcional; sem runtime, sem guard fake,
  sem RF5 validado; contexto/guard e execução real com revalidação pendentes (Bloco D).
- APIs finais usadas: `ActionCableListener.instance#message_created`,
  `enqueued_jobs`, `ActiveJob::Arguments.deserialize`, JSON round-trip,
  `ActiveJob::Base.execute`, `ActiveJob::Core#serialize` (legado),
  `allow(ActionCable.server).to receive(:broadcast)` (boundary).
