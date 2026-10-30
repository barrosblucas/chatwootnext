# T0.2 parte A — escopo de conversas no spike G0 (2026-10-22)

**Estado: PARCIAL.** T0.2 segue ABERTO. G0 segue ABERTO. Esta entrega cobre só a primeira parte do T0.2: policy, query e HTTP de conversas, com dois setores (A e B) na mesma inbox WhatsApp. Socket, anexos, contatos, busca detalhada, notificações, exports, integrações e QR/status ficam para a parte B. T0.3, T0.6 e T0.7 não foram tocados.

Autorização: a mesma citação do briefing (alvo local, banco `conecta_baileys_g0_test`, Postgres `127.0.0.1:55432`, Redis `127.0.0.1:56379`). Sem dado real, sem produção, sem remoto, sem alteração de `db/schema.rb`, sem migração produtiva, sem commit.

## 1. O que foi provado (spec `spec/connecta/scope_policy_query_spec.rb`)

Executado pelo runner oficial, com o Ruby 3.4.4 do cache: **30 exemplos, 0 falhas**.

- Fixture: 1 conta; inbox WhatsApp `Channel::Whatsapp` provider `baileys` gravada sem validar credenciais (sem rede); inbox de controle nativa, não marcada; setores `raiz`, `a`, `a1` (filho de A), `b`; conversas A, A1, B, transferida (A) e órfã (sem escopo) na inbox marcada; conversa de controle na inbox não marcada.
- Atores: agente A (grant `atender` em A), agente B (`atender` em B), gestor A (`acompanhar` em A, agent nativo), membro sem grant, admin nominal sintético (`admin_nominal` na raiz). Todos são membros da mesma inbox WhatsApp.
- Hooks reais prepended no instalador (`Connecta::Scope::Installer.install!`, chamado só pelo spec): `ConversationPolicy#show?`, `Conversations::PermissionFilterService#perform` (filtro antes de paginação e contagem), `ConversationsController#toggle_status/update`, `MessagesController#create`, `AssignmentsController#create`.

Contagens de asserção:
- 13 respostas HTTP 200 esperadas (leituras permitidas, envio e encerramento pelo agente com grant, controle nativo, admin nominal).
- 15 respostas HTTP 401 esperadas (negações: leitura cruzada, membro sem grant, gestor escrevendo, transferido, órfão, admin_only, transferring, heartbeat, revogação).
- 4 asserções diretas da policy real (2 permitem, 2 negam).
- 5 exemplos que comprovam mudança de contagem (`Message`); 3 que comprovam que nada mudou (escrita negada).
- 4 asserções de auditoria (`access_audits`), incluindo a negação de escrita do gestor.
- Índices: 2 violações esperadas (`RecordNotUnique`) e 1 liberação após estado terminal; registro de auditoria é append-only (`ReadOnlyRecord`).

Casos cobertos:
- Agente A lê A e descendente A, não lê B nem a transferida; lista e detalhe batem (`all_count` 3 com o controle nativo).
- Agente B lê só B (`all_count` 1), mesmo sendo membro da mesma inbox.
- Gestor A lê A e A1, não lê B (conteúdo nem metadados), não envia, não encerra, não atribui.
- Membro sem grant: lista vazia na inbox marcada, detalhe 401.
- Admin nominal: lê todas as conversas da inbox marcada, inclusive a órfã e a transferida; cada listagem e leitura fica auditada.
- Paginação com `CONVERSATION_RESULTS_PER_PAGE=1`: três páginas trazem exatamente A, A1 e controle; o filtro é aplicado antes da paginação.
- Ator e setor forjados (`actor_id`, `org_unit_id`, `sector`, `user_id`, cabeçalhos `X-Connecta-*`) não ampliam o acesso do agente B.
- Escopo ausente na inbox marcada: só admin nominal lê.
- `transferred_out` não dá acesso ao agente com grant.
- `transferring`: leitura permitida, envio bloqueado.
- `admin_only`: agentes negados, admin nominal lê.
- `maintenance`: não-admin negado na inbox marcada; a inbox de controle continua nativa.
- Heartbeat vencido (10 min, TTL 5 min): não-admin negado; admin nominal lê.
- Revogação local (`revoked_locally_at`) vale na requisição seguinte, sem cache.
- Controle nativo: inbox não marcada segue a regra nativa (membro lê e envia; não membro é negado).

## 2. Prova de dependência dos hooks (mutação)

Com `install!` desabilitado no próprio arquivo (temporário, restaurado em seguida, conferido com `grep`), o mesmo spec deu **23 falhas de 30** (`.context/evidence/g0/06-logs/mutacao-sem-hooks.log`). As 7 que passam são as de comportamento nativo (controle e escritas nativas). Ou seja: as negações vêm das classes reais, não de mock.

## 3. Modelo e runner

- Tabelas do protótipo (prefixo `connecta_g0_*`, criadas só pelo helper, create-only): `scoped_inboxes`, `org_units`, `user_grants`, `user_auth_epochs`, `acl_sync_state`, `conversation_scopes`, `access_audits`.
- Índices: `conversation_scopes.conversation_id` único; `(inbox_id, contact_id)` único parcial com `state IN ('reception','active','transferring','pending_activation','activation_stuck')`.
- Runner `scripts/connecta/g0_test_env.sh`: mudança mínima. O núcleo continua validado contra `db/schema.rb` (mesma comparação de antes, agora excluindo `connecta_g0_%`); as tabelas `connecta_g0_*` só são aceitas se estiverem na lista fixa `G0_EXTRA_TABLES` (7 nomes). Nenhum check de banco ou de posse foi desabilitado. Motivo: sem isso o `--spec` recusa o banco ("diverge"), porque o check exige que o `public` tenha exatamente as tabelas do schema. Decisão registrada em `.context/decisions/001-runner-aceita-extras-g0.md`.
- O guarda `spec/support/connecta/g0_target_guard.rb` **não foi alterado**.

## 4. Baseline durável (antes e depois)

Arquivos: `.context/evidence/g0/06-baseline-logs/state-antes.txt` e `state-depois.txt`; hashes de arquivos em `sha256-antes.txt`.

| Item | Antes | Depois |
|---|---|---|
| Canário (comentário do banco) | `g0-canario-sintetico-2026-10-22` | igual |
| `schema_migrations` | 185 | 185 |
| `schema_sha1` | `d72f597…` | igual |
| Tabelas do núcleo (`public`, sem `connecta_g0_*`) | 112 | 112 |
| Tabelas `connecta_g0_*` | 0 | 7 (create-only) |
| Hash do schema do núcleo (`pg_dump --schema-only -T 'connecta_g0_*'`, sem linhas `\restrict`) | `80ced235…` | `80ced235…` (igual) |
| Linhas em contas, usuários, inboxes, conversas, account_users | 0 | 0 |
| Linhas nas tabelas G0 | — | 0 (transações de teste revertidas) |

`db/schema.rb`: sem alteração (`git diff --stat` vazio). Nenhum DROP, TRUNCATE ou reset.

## 5. Validações

- `scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_policy_query_spec.rb`: 30 exemplos, 0 falhas, exit 0 (`run-4.log`; as rodadas anteriores `run-1` a `run-3` foram de correção de fixture e de expectativa, documentadas no mesmo diretório).
- `scripts/connecta/g0_test_env.sh --spec` (dry-run, depois): `ok: banco de teste com schema esperado` (`dry-run-spec-depois.log`).
- Regressão do runner: `scripts/connecta/g0_test_env.sh --spec --apply` (T0.1, `route_inventory_spec`): 3 exemplos, 0 falhas, exit 0 (`regressao-t0-1-route-inventory.log`).
- T0.4 e T0.5 não foram repetidos: não mudam guarda nem hooks, e os hooks só são instalados pelo spec de escopo.
- RuboCop (`bundle exec rubocop`, ambiente `env -i` com o Ruby 3.4.4): 20 arquivos inspecionados, sem ofensas (novos arquivos de `app/services/connecta/scope/`, spec e helper).

## 6. Superfícies ainda fora desta parte (pendências exatas)

- **Filtro avançado `POST conversations/filter`** (`app/controllers/api/v1/accounts/conversations_controller.rb:55`, usa `Conversations::FilterService`): não hookado. Pode listar conversas de inbox marcada para agente sem grant. Próxima atribuição, antes de qualquer gate.
- **Conversas e mensagens não exercitadas por HTTP nesta parte**: `GET messages`, `PATCH/DELETE messages`, `attachments`, `draft`, `scheduled_messages`, `participants`, `labels`, `mute`, `transcript`, `typing`, `presence`, `unread_counts`. O `show?` do `Conversations::BaseController` (`:8`) cobre as ações desse controlador; ainda não há prova HTTP.
- **Endpoints `meta` e `search`**: usam o mesmo `ConversationFinder#perform`/`perform_meta_only`, portanto passam pelo mesmo hook, mas não há exemplo HTTP.
- **Criação de conversa e `Api::V1::Accounts::Conversations::ConnectaTransfersController`**: fora (T0.3). Não há gate de escrita nessas rotas; a leitura passa pelo `show?` do `BaseController`.
- **Socket, anexos, contatos, busca detalhada, notificações, exports, integrações, QR/status**: parte B do T0.2.
- **Matriz completa de superfícies (plano §10.1)**: não lida nesta atribuição (briefing pediu requisitos autossuficientes). Não há afirmação de cobertura da matriz.
- **Fixture de auto-atribuição**: criar conversa extra na inbox WhatsApp de teste falhou em `AutoAssignment::InboxRoundRobinService#add_agent_to_queue` (`lpush` sem valores no MockRedis). O spec reaproveita as conversas já criadas; a causa não foi investigada.
- **Hooks são de spike**: instalados só por `Connecta::Scope::Installer.install!` (`Rails.env.test?`); produção não os carrega. A integração produtiva é Fase 3.

## 7. Decisões de implementação (sem humano no meio)

- Admin nominal: grant `admin_nominal` explícito na projeção; só lê, com auditoria. Agente ou gestor nativo nunca vira admin.
- Inbox marcada não usa o papel nativo de administrador: só a projeção decide.
- Escrita exige `state = active` e `case_version > 0`; `transferring` bloqueia escrita e permite leitura.
- Verificação de vínculo: linha em `user_auth_epochs` sem `revoked_locally_at`. A coluna `epoch` é gravada, mas não entra na decisão nesta parte.
- Heartbeat vencido: `acl_sync_state.last_heartbeat_at` mais antigo que 5 minutos nega não-admin.
- Histórico de auditoria: decisões de agente em inbox marcada são gravadas por exemplo (`access_path`: `detail`, `message_create`, `conversation_status`, `conversation_update`, `conversation_assign`); listagens só são auditadas para admin (uma linha por listagem, `conversation_id` nulo).

## 8. Arquivos

Novos:
- `app/services/connecta/scope/`: `base_record.rb`, `scoped_inbox.rb`, `org_unit.rb`, `user_grant.rb`, `user_auth_epoch.rb`, `acl_sync_state.rb`, `conversation_scope.rb`, `access_audit.rb` (modelos do protótipo); `projection.rb` (leituras frescas), `gate.rb` (decisão e auditoria), `conversation_query.rb` (filtro antes da paginação); `policy_hook.rb`, `finder_hook.rb`, `write_guard.rb`, `conversation_write_hook.rb`, `message_write_hook.rb`, `assignment_write_hook.rb` (hooks prepended); `installer.rb`.
- `spec/connecta/scope_policy_query_spec.rb` (30 exemplos).
- `spec/connecta/support/g0_scope_schema.rb` (create-only, idempotente).
- `.context/evidence/g0/06-scope-policy-query.md` (este arquivo) e `06-baseline-logs/`, `06-logs/`.

Alterados (não rastreados):
- `scripts/connecta/g0_test_env.sh`: constante `G0_EXTRA_TABLES`; check `db_state` com exclusão dos `connecta_g0_%` do núcleo e checagem de extras.

Não alterados: `db/schema.rb`, controllers, policies e finders existentes, `spec/support/connecta/g0_target_guard.rb`, `spec/requests/connecta/route_inventory_spec.rb`, compose, `.env*`.
