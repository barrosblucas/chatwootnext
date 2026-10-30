# 40 — RF4 HTTP existente (TASK_ID g0-rf4-a3-spec) — ESCRITO E NÃO EXECUTADO

Somente escopo autorizado: 1 spec nova + este doc + append no changelog do dia.
A1/A2 ficam para código posterior; runtime adiado ao Bloco D pela direção humana
("primeiro executa tudo, depois testa"). Nenhum RF4 marcado como validado.
Sem Gate/Finder/Controller stubado; sem jobs reais; sem testes executados.

## 1. Spec nova (casos ESCRITOS e NÃO EXECUTADOS; execução pendente)

- Arquivo: `spec/connecta/scope_notification_existing_spec.rb` (untracked `??`).
- Cabeçalho idêntico ao estável `spec/connecta/scope_notifications_spec.rb:1-13`
  (`g0_target_guard`, `rails_helper`, `g0_scope_schema`, `g0_scope_fixture`,
  `G0ScopeSchema.ensure!`, `Installer.install!`); factory nativa
  `create(:notification, user:, account:, primary_actor: conv)` (`spec/factories/notifications.rb:4-11`).
- Rotas nativas reais, todas cobertas em `config/routes.rb:378-388`:
  `GET index`, `GET unread_count`, `PATCH update`, `POST snooze`, `POST unread`, `DELETE destroy`.
  Contratos de resposta reais: lista `index.json.jbuilder:1-28`
  (`data.meta.count/unread_count/current_page`, `data.payload[]` com `primary_actor_*`),
  `unread_count` responde inteiro nu via `render json: @unread_count`
  (`notifications_controller.rb:51-54`), `update/unread/snooze` devolvem o JSON da linha
  (`notifications_controller.rb:27-35,56-60`), `destroy` devolve `head :ok`.
- Isolamento ephemeral sem DB destrutivo: `clear_enqueued_jobs` no `before` e no `after`
  (test adapter nativo; `after_create_commit` enfileira `PushNotificationJob`/
  `EmailNotificationJob`/`RemoveDuplicateNotificationJob` em `notification.rb:58,183-191`,
  sem execução aqui — jobs nunca rodados, só limpos da fila).
- Casos (8 `it`,erdados contra o filtro futuro A1/A2, que roda antes da paginação):
  1. Revoga grant de A com 16 de `conv_a` + 1 controle: lista só o controle, `meta.count`=1,
     `unread_count`=1, página 2 vazia; `Notification.where(user: A).count`=17, história intacta.
     Controle paginado MAIS ANTIGO (`last_activity_at`/`created_at`/`updated_at` no passado via
     `update!`) para que a filtragem APÓS a página esconda o visível (AC1 pega o bug de filtrar
     depois de paginar). Membro sem grant em page 2 não recebe ID oculto.
  2. Transferência por scope (`org_unit: org_b`, `state: transferred_out`, via fixture AR —
     sem LocalTransaction RF6): A não lista nem conta `conv_a`, controle preservado,
     `read_at` da linha oculta segue nil.
  3. Admin nominal: não lista marcada (`count`=0, `unread_count`=0) nem grava audit allow
     indevido (`AccessAudit` com `access_path: 'list'` = 0); linha marcada intacta.
     Membro sem grant segue nativo no controle (`conv_control`).
  4. Controle: membro sem grant com `conv_control` lista/count/unread = 1 (regra nativa).
  5. PATCH oculta → 404 sem `read_at`; visível → 200 com `read_at`; oculta segue nil.
  6. `POST snooze` oculta → 404 sem `snoozed_until`; visível → 200 com `snoozed_until`.
  7. `POST unread` oculta (lida) → 404 sem remarcar; visível (lida) → 200 com `read_at` nil.
  8. `DELETE` oculta → 404 sem apagar; visível → 200 apagando só a própria linha.
- Nenhum caso marca RF4 como validado; implementação A1/A2 e runtime pendentes (Bloco D).

## 2. Checagens reais desta tarefa (1 alvo, sem runtime)

Comandos (caminhos absolutos, receita `scripts/connecta/g0_test_env.sh:47-49` + `gotchas.md:43`):

```sh
/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c spec/connecta/scope_notification_existing_spec.rb
env -i PATH=.../ruby/3.4.4/bin:... BUNDLE_GEMFILE=... BUNDLE_PATH=... BUNDLE_FROZEN=true bundle exec rubocop <nova spec>
git diff --no-index --check /dev/null <nova spec>
git diff --check
git status --short
df -h /tmp
```

- Resultado factual: `ruby -c` 3.4.4 `Syntax OK`, EXIT 0; RuboCop check-only `env -i` +
  BUNDLE do launcher só na nova spec → **1 arquivo, 0 ofensas**, EXIT 0, stderr vazio.
  Antes: 6 ofensas (HashAlignment no helper, 3 SkipsModelValidations em
  `update_all`/`update_columns`, 2 MultipleExpectations nos casos de paginação/admin);
  depois: 0, sem tocar helpers compartilhados.
  Correções mínimas só no arquivo novo: helper `create` em 3 linhas (HashAlignment),
  `mark_all_unread!` e ordenação determinística via `update!` por instância
  (SkipsModelValidations some sem bulk), disable de arquivo
  `RSpec/MultipleExpectations` com `enable` no fim (casos AC1/AC2 juntam
  lista+count+unread+efeitos por caso, mesmo padrão do `captain_scope_spec.rb:321`).
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

- Plano rev. 2 `.context/plans/2026-10-24-g0-rf4-rf5-pending-deliveries.md:111-119` (A3).
- Juiz R1 `.context/evidence/g0/36-juiz-r1.md:7` (RF4: Gate só na criação; lista/contagem
  e push/email pendentes sem revalidação).
- Estáveis, só leitura: `spec/connecta/scope_notifications_spec.rb` (padrões factory/API),
  `app/controllers/api/v1/accounts/notifications_controller.rb` (rotas/metacampos),
  `app/finders/notification_finder.rb` (lista/contagem nativas), `app/views/.../index.json.jbuilder`,
  `spec/connecta/support/g0_scope_fixture.rb` (setores/controle/grants), `app/models/notification.rb`.
- RF2 (`scope_contact_fields_spec.rb`, outro Coder) e RF3 (ContactHook/CreateSpec) NÃO tocados.
- Limite honesto: sintaxe/estilo ≠ prova funcional; sem runtime, sem Gate fake, sem RF4 validado.
