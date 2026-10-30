VERDICT: REJECTED
REASONS:

- **AC1/T0.2 — Copilot permite vazamento entre setores.** `SearchContacts.execute()` sem filtros passa pelo guard; numa busca ampla, basta existir um contato permitido para liberar a consulta inteira. Exemplo: buscar “Maria” pode devolver contatos de A e B ao agente A. Evidências: `app/services/connecta/scope/copilot_tool_hook.rb:47`, `app/services/connecta/scope/copilot_tool_hook.rb:59`, `enterprise/app/services/captain/tools/copilot/search_contacts_service.rb:12`.
- **AC1/T0.2 — dados globais do contato continuam expostos.** O agente autorizado a visualizar um contato recebe `custom_attributes`; pelo Copilot, recebe também todas as notas. Isso contraria a matriz §10.1. Evidências: `app/services/connecta/scope/contact_visibility.rb:22`, `app/views/api/v1/models/_contact.json.jbuilder:11`, `enterprise/app/services/captain/tools/copilot/get_contact_service.rb:12`, `app/services/llm_formatter/contact_llm_formatter.rb:20`.
- **AC1/T0.2 — criação de contato contorna a guarda do provedor.** `POST contacts` com telefone e `inbox_id` marcado não passa por `fetch_contact`; a autorização nativa permite criar, e o builder chama `on_whatsapp`. Portanto, a pendência documentada representa um caminho concreto sem bloqueio anterior ao efeito. Evidências: `app/controllers/api/v1/accounts/contacts_controller.rb:16`, `app/controllers/api/v1/accounts/contacts_controller.rb:94`, `app/policies/contact_policy.rb:42`, `app/builders/contact_inbox_builder.rb:40`.
- **AC1/T0.2 — notificações anteriores sobrevivem à perda de acesso.** O Gate atua na criação, mas a listagem busca notificações por usuário/conta e serializa conteúdo sem revalidar o escopo. Push/email pendentes também seguem sem essa verificação. Exemplo: revogar o grant de A não impede consultar uma notificação já criada. Evidências: `app/services/connecta/scope/notification_hook.rb:3`, `app/finders/notification_finder.rb:39`, `app/views/api/v1/accounts/notifications/index.json.jbuilder:13`, `app/jobs/notification/push_notification_job.rb:4`, `app/services/notification/email_notification_service.rb:4`.
- **AC1/T0.2 — socket pendente não revalida destinatários.** O listener captura tokens autorizados, mas o job posterior transmite para esses mesmos tokens; em atualizações, ainda relê o conteúdo atual da conversa. Uma revogação entre enqueue e execução não impede a entrega. O spec verifica apenas o próximo evento. Evidências: `app/services/connecta/scope/socket_hook.rb:60`, `app/listeners/action_cable_listener.rb:363`, `app/jobs/action_cable_broadcast_job.rb:25`, `app/jobs/action_cable_broadcast_job.rb:39`, `spec/connecta/scope_socket_spec.rb:119`.
- **AC3/T0.7 — ativação não é idempotente.** A primeira chamada muda o registro para `committed`; repetir `activate!(case_version: 2)` procura exclusivamente `committed_local` e lança `RecordNotFound`. Evidência: `app/services/connecta/transfer/local_transaction.rb:144`.
- **AC2/T0.3 — prova local satisfatória.** Incoming e transferência compartilham o lock inbox/contato, mantido até o commit. O spec verifica quantidade bruta antes da deduplicação, distribuição temporal, falhas de threads e limpeza restrita. Evidências: `app/services/connecta/transfer/incoming_hook.rb:7`, `app/services/connecta/transfer/local_transaction.rb:165`, `spec/connecta/transfer_cutover_spec.rb:153`, `spec/connecta/transfer_cutover_spec.rb:165`.
- **AC4 — decisão suficiente para viabilidade exclusivamente local.** `R-G0-LOCAL-1` cobre retrabalho reversível com transporte desconhecido sem execução; preserva as lacunas EVID e exige autorização escrita antes do uso real. Não constitui aceite humano de risco produtivo. Evidência: `.context/evidence/g0/22-quadro-evidencias.md:19`.
- **AC5/AC6 — evidências e escopo conferidos.** Os oito logs sustentam 456 execuções, 390 exemplos únicos e 19 specs; JSON confirma Ruby 3.4.4, 73 arquivos e zero ofensas. HEAD coincide com o baseline; status contém somente os sete grupos previstos, sem diff rastreado. Changelog presente. Evidências: `.context/evidence/g0/34-logs/manifest.tsv:2`, `.context/evidence/g0/33-logs/rubocop-final-4.json:1`, `.context/evidence/g0/00-baseline-preparo.md:6`, `.context/changelog/CHANGELOG_2026_10_24.md:191`.

REQUIRED_FIXES:

1. **AC1:** filtrar cada resultado de `SearchContacts` pelo escopo autorizado. Cobrir busca sem filtros e nome compartilhado entre A/B; nenhum contato alheio pode chegar ao modelo.
2. **AC1:** ocultar notas e atributos globais dos contatos para usuários somente escopados, inclusive nas respostas HTTP e ferramentas Copilot.
3. **AC1:** proteger `POST contacts` com inbox marcada antes de persistência/provedor. Provar que membro sem grant é negado sem chamada ao transporte nem criação/mesclagem.
4. **AC1:** revalidar notificações existentes e entregas pendentes após revogação/transferência. Listagem, contagem e entrega não podem revelar conteúdo cujo acesso foi perdido.
5. **AC1:** impedir broadcasts pendentes para destinatários que perderam acesso. Cobrir enqueue autorizado → revogação → execução real do job, inclusive eventos que recarregam a conversa.
6. **AC3:** aceitar repetição da ativação com a mesma versão confirmada sem erro ou efeitos adicionais; manter rejeição de versão diferente. Acrescentar regressão específica.

VALIDATIONS:

- Revisão somente leitura dos hooks, serviços, specs, callers e overlay Enterprise citados.
- Conferência dos oito logs, manifest, JSON RuboCop e registro de sintaxe/whitespace.
- `git status`, diff normal/staged, `git diff --check` e HEAD contra baseline.
- Nenhum arquivo alterado; nenhum teste, build, lint, SQL, Docker ou acesso remoto executado. Resultados de execução foram avaliados pelos logs fornecidos.

MISSING_EVIDENCE:

- none

SUGGESTIONS:

- **AC7:** manter como backlog os achados preexistentes 8–11, a presença com IDs/sinal (`app/channels/room_channel.rb:22`), o frontend com metadados reduzidos e a decisão produtiva sobre o job separado (`.context/evidence/g0/35-gate-g0-dossie.md:109`). Não fundamentam esta rejeição.
- Atualizar referências históricas de “não validado” quando já superadas pelos logs finais, preservando T0.6 como pendente. O atraso autorizado de `PROJECT_STATE.md` não bloqueia o Gate.