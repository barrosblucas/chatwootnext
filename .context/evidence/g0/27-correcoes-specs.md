# 27 — Correções de setup/expressão/contrato antigo nos 3 specs do lote B (g0-fix-scope-specs)

Correções SOMENTE de spec. Nenhum código `app`/installer, suporte compartilhado ou
outro spec alterado. Nenhum spec executado nesta tarefa (código global em mutação
por outra frente); prova funcional pendente em validação consolidada posterior.

## 1. `spec/connecta/scope_b1_leftovers_spec.rb:141` — expressão RSpec inválida

- Falha: `NoMethodError: undefined method 'not_to'` em
  `expect { ... }.not_to change(...).and not_to have_enqueued_job(...)`.
  O `and` fora do matcher encadeia um `not_to` solto no exemplo (log
  `26-logs/escopo-lote-b-1.log:36-45`, mapeado em `26-validacao-escopo-novo.md:109-111`).
- Correção (só setup/expressão): dois blocos `expect { post ...; expect 403 }.not_to ...`,
  um para `change(Message, :count)` e outro para `have_enqueued_job(SendReplyJob)`,
  cada um com `expect(response).to have_http_status(:forbidden)` dentro do bloco.
- Intenção preservada: gestor em conversa de A → 403, sem criar reação nem
  enfileirar envio. Nenhuma expectativa de autorização enfraquecida.

## 2. `spec/connecta/scope_team_contact_spec.rb:54/94/134/223/235/258/270/285/305` — `lpush` do MockRedis via atribuição automática

- Falha: `Redis::CommandError: ERR wrong number of arguments for 'lpush' command`
  em `auto_assignment/inbox_round_robin_service.rb:11` (`Redis::Alfred.lpush(key, values)`
  passa array; o `MockRedis` de teste exige 1 valor por chamada). Caminhos:
  `assignment_handler.rb:27` (`ensure_assignee_is_from_team` no `conv.update!(team:)`)
  e `auto_assignment_handler.rb:26` (`run_auto_assignment` na factory
  `create(:conversation)`), ambos caindo em `reset_queue` → `add_agent_to_queue(array)`
  com a fila vazia (log `26-logs/escopo-lote-b-1.log:47-389`, mapeado em
  `26-validacao-escopo-novo.md:112-130`).
- Por que setup real: o `lpush` quebrado NÃO é comportamento relevante sob teste.
  A fila round-robin pertence ao subsistema legado de auto-atribuição, que estes
  specs não exercem (nenhum caso cria membro novo, muda `assignee` ou verifica
  distribuição/fila). O Gate/Controller/SocketHook sob teste continuam reais e
  sem stub; só o gatilho colateral de atribuição é desligado.
- Correção (só fixture local, sem tocar suporte compartilhado):
  `Team.create!(..., allow_auto_assign: false)` + `before` local com
  `whatsapp_inbox.update!(enable_auto_assignment: false)` e
  `control_inbox.update!(enable_auto_assignment: false)` na parte request e na
  parte `ActionCableListener` (a factory `create_marked_linked_contact!` também
  passa por `run_auto_assignment`). Coerente com o padrão já usado em
  `scope_http_filter_spec.rb:17-21` e `scope_related_http_spec.rb:69-72`
  (assignee/responsável explícito para não entrar no round-robin); aqui o flag
  desliga o gatilho na origem porque os casos precisam de `conv.update!(team:)`
  e de factory sem assignee.
- Casos preservados: `team_id` topo/null/mesmo-valor/aninhado (422 sem gravar nem
  enfileirar, lote misto sem aplicar nada), fora do escopo 404, controle nativo,
  snapshot `contact.deleted` (destinatários agent_a+manager_a, sem admins/PII,
  sem stream da conta, sem rede, Gate ligado). Se algum `lpush` futuro for
  comportamento relevante real que não possa ser isolado, reportar em vez de mascarar.

## 3. `spec/connecta/scope_b2_complements_spec.rb:117/:122` — caracterização antiga de `inbox_update`

- Falha: auditoria `allow` (`surface: inbox`, `access_path: inbox_update`) contou 0,
  esperava 1 (log `26-logs/escopo-lote-b-1.log:391-401`, mapeado em
  `26-validacao-escopo-novo.md:132-136`). O código c7b (`evidência 19 §3`)
  moveu a auditoria para depois da autorização (`InboxHook#check_authorization`:
  `super` primeiro, só sem exceção o pendente vira `allow`; com
  `Pundit::NotAuthorizedError` o pendente é descartado).
- Correção (só contrato, sem mexer em expectativas de acesso): o caso agora exige
  o contrato desejado — admin nominal com papel de agente recebe 401 do nativo,
  nome intacto, **nenhum** `allow` em `inbox_update` (contagem `allow` = 0 e
  contagem total do `access_path` = 0). Título `ACHADO:` removido (não é mais
  caracterização de vazamento). Status nativo de negação (401) e demais casos
  (positivos com grant, webhooks, relatórios) mantidos.

## Validação nesta tarefa (sem executar specs)

- `git diff --check`: limpo (EXIT 0).
- `git status --short`: só os `??` pré-existentes (nenhum rastreado modificado).
- `ruby -c` com `/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby`:
  os 3 specs → `Syntax OK` (EXIT 0 cada).
- `df -h /tmp`: leitura, sem apagar (tmpfs 7.6G, 67% usado).
- Specs NÃO executados (código global em mutação por outra frente); execução
  pendente na validação consolidada.
