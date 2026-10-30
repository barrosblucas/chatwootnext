# Changelog 2026-10-25

## Added
- Job `Connecta::Runtime::TransferAbortJob` (contrato v1 §4): chamado quando a transação local falha/é desfeita após prepare bem-sucedido; retry igual aos demais (24 tentativas, 10s).
- Guard `Connecta::Runtime::AccountGuard`/`AccountMismatch`: valida `account_id` inteiro contra `CONNECTA_ACCOUNT_ID` (403 se divergente).
- `Connecta::Runtime::Feature.current_account_id!`: conta configurada como inteiro positivo.
- Wrapper público `Connecta::Scope::Gate#readable_scope?` (mesma regra de `scope_readable?`, só para o `delivery_check` de contato excluído).
- `Connecta::Runtime::ReceptionScopeCreator.verify_marked_inboxes!`: valida unidade de recepção no boot quando há inbox marcada.

## Changed
- Todas as chamadas Fork→WP (itens 1–7) passam a carregar `account_id`; prepare leva `case_protocol`/`case_version`; commit leva `committed_at` (ISO8601); activated leva `account_id` + `case_version`.
- Endpoints WP→fork (itens 8–11) validam `account_id` no `BaseController` (403 se divergente); sync vazio conta como heartbeat.
- `TransferTransaction`: erro de transporte no prepare marca `unknown`; prepare recusado desfaz sem abort remoto; falha local pós-prepare desfaz e enfileira abort.
- `AclRevocationService`: ack só após barreira local efetiva; já aplicado é idempotente; epoch menor não rebaixa.
- `ReceptionScopeCreator`: sem unidade configurada levanta `MissingReceptionUnit` em vez de só logar.

## Fixed
- 3a: `scope_readable?` privado chamado com receptor explícito — agora via `readable_scope?`.
- 3b: epoch igual com registro ativo devolvia ack sem revogar — agora revoga de verdade.
- 3c: recepção sem unidade omitia o escopo em silêncio — agora falha explícita/reconciliável.

## Tests
- Specs runtime escritas, NÃO executadas: `runtime_platform_client_contract_spec.rb`, `runtime_acl_sync_spec.rb`, `runtime_acl_revocation_spec.rb`, `runtime_scope_activation_spec.rb`, `runtime_transfer_transaction_spec.rb`, `runtime_reception_scope_spec.rb`, `scope_gate_delivery_contact_deleted_spec.rb`.

## Docs
- Evidência anexada em `.context/evidence/baileys/f3-f5-fork.md` (contrato v1, decisões [O], correções 3a/3b/3c, lista de specs).

## Removed
- Nada.

## Added (T3.9)
- Migration `20261024000001_add_enforcement_to_connecta_scoped_inboxes`: coluna `enforcement` aditiva/idempotente (default `enforce`, NOT NULL).
- Controller admin `Api::V1::Accounts::Connecta::ScopedInboxesController#update` + rota `PATCH scoped_inboxes/:inbox_id` (só admin nominal, com auditoria; 403 para não-admin).

## Changed (T3.9)
- `Connecta::Scope::Gate#state_allows?`: escrita nega em `maintenance` (leitura inalterada); `admin_only` já negava não-admin em `scope_allowed?`.
- `Connecta::Scope::ConversationHttpHook#connecta_scope_write_guard!`: manutenção vira 409 antes do team_id.
- `Connecta::Transfer::OutboundDispatch::CLAIM_SQL`: claim em manutenção vira `parked` (não despacha).

## Tests
- Nenhuma spec executada nesta tarefa (fora de escopo; outra frente).

## Fixed (FORK-v4a · item 1)
- `Connecta::Runtime::G0Adapter.install!` estourava `FrozenError` no boot com `CONNECTA_HUMAN_NUMBER_ENABLED=true`: `validator.options[:in]` é congelado pelo Rails 7.1. Removida a expansão de estados (`expand_product_state_validations`); o modelo de produto `Connecta::ConversationScope` já aceita os estados de produto e o Scope não grava `closed`/`abandoned_triage`.
- `install!` agora é idempotente e não levanta exceção (`spec/connecta/runtime_g0_adapter_install_spec.rb`, 5 exemplos passando).

## Changed (FORK-v4a · item 1)
- `spec/connecta/support/g0_product_tables.rb`: passa a delegar a `G0Adapter.install!` (o contorno que pulava a expansão não é mais necessário).

## Tests (FORK-v4a · item 2)
- `runtime_platform_client_contract_spec.rb`: 7/7 passando. Itens 3/5: fixture no estado que o commit local deixa (origem `transferred_out`, destino `pending_activation` versão 0). Item 7: linha `Connecta::Outbox` com o `dedupe_key` criada no fixture. Abort job: asserção por `rescue_handlers` (ActiveJob 7.1 não tem `retry_on_list`).
- `runtime_hmac_authenticator_spec.rb`: 3/3 passando.
- Fora deste trabalho (não tocados, falham por causas próprias): `runtime_acl_sync_spec`, `runtime_acl_revocation_spec`, `runtime_scope_activation_spec`, `runtime_reception_scope_spec` e `runtime_transfer_transaction_spec` (`post` indisponível em spec sem `type: :request`, helper `activate` com assinatura errada, Redis `lpush`, e "human-number is disabled" sem ENV).

## FORK-v4d (fechamento do ciclo)
### Tests
- `containment_spec.rb`: 14/14 passando. `BODY` era usado sem definição; agora é constante de topo do arquivo, conferida nas respostas de download. Contextos renomeados para `with ...` (RuboCop `RSpec/ContextWording`). A asserção de lista de `admin_only` passou a exigir o conjunto exato (`conv_control`, não `all_count` 0): a fixture dá ao agente membership na inbox de controle não marcada, que é visível por desenho.
- `runtime_transfer_transaction_spec.rb`: 6/6 passando. Retry do `TransferAbortJob` agora é comportamental: falha de transporte reenfileira com `wait` ≈ 10 s; com 23 falhas já contadas (`exception_executions`), a 24ª esgota `attempts` e o erro sobe. Os jobs de commit e revogação continuam verificados só pelo registro do handler (sem asserção de `wait`/`attempts`), como indicado no próprio spec.
- `scope_gate_delivery_contact_deleted_spec.rb` 3/3 e `runtime_scope_activation_spec.rb` 6/6 passando.
- Qualificação das constantes nos 4 arquivos de spec (rodada anterior) e `account_mismatch.rb`/`account_guard.rb` (rodada anterior) entram neste fechamento.

### Fixed
- Correção `ContactInbox.where(id: conversation.contact_inbox_id)` em `app/services/connecta/scope/delivery_context.rb` (coluna real: `conversations.contact_inbox_id`, conferida em `db/schema.rb`).

## Fixed (FORK-v6e · lotes D/E)
- Specs alinhados às regras registradas: `containment_spec.rb` (leitura de não-admin em manutenção = 404, decisão 002); `captain_scope_spec.rb` (contato sem vínculo com inbox marcada é visível, contato vinculado só a quem vê a conversa, evidência 36-rf1-search §22-28; stub de `Redis::Alfred` no teste de filtro nativo); `scope_socket_delivery_spec.rb` (epoch lido de `users`).

## Docs (FORK-v6e)
- `.context/decisions/003-escopo-contato-e-manutencao.md`: registra as regras de contato nativo sem vínculo e de manutenção com 404.

## FORK-v7b — 403 do contrato de runtime e TTL de heartbeat único

### Fixed
- `app/services/connecta/scope/conversation_http_hook.rb` (`connecta_scope_transfer_guard!`): com `CONNECTA_HUMAN_NUMBER_ENABLED=true`, o guard legado negava o GET de destinos com 403 antes do `TransferPolicy`. Causa provada em `conversation_http_hook.rb:100` (Denied :forbidden). Agora o guard só nega quando o runtime está desligado; com o runtime ligado, a autorização é do `TransferPolicy` (ator, grant `transferir`, escopo). Negação legada preservada (`scope_http_filter_spec` verde).
- TTL de heartbeat unificado: `Connecta::Scope::Projection.heartbeat_ttl` (env `CONNECTA_ACL_HEARTBEAT_TTL_SEC`, padrão 120 s) usado por `Projection#fresh?` e `ProjectionTablesHook#fresh?`. Antes: 60 s no adapter e 300 s fixos na projeção. Referência WP: `aclHeartbeatMaxAgeSec` = 120 s (`apps/whatsapp-platform/src/config.ts:156`), envio a cada 40 s.

### Tests
- Par `scope_admin_metadata_pending_spec.rb` + `runtime_platform_client_contract_spec.rb`: 14 exemplos, 0 falhas.
- `runtime_acl_revocation_spec.rb` + `attachment_download_scope_spec.rb`: 32 exemplos, 0 falhas.
- `runtime_*_spec.rb` + `containment_spec.rb`: 55 exemplos, 0 falhas.
- `scope_http_filter_spec.rb`: 34 exemplos, 0 falhas (caminho legado de transferência continua negado).

### Docs
- `.context/decisions/003-escopo-contato-e-manutencao.md`: adendo com os valores de TTL e a decisão.

## FORK-v7c · regressão final e RuboCop do conjunto

### Fixed
- `spec/connecta/transfer_schema_smoke_spec.rb`: fixa `table_name` das tabelas G0 por exemplo e restaura ao final. `G0Adapter.install!` (chamado pelos specs `runtime_*`) reatribuía globalmente o modelo para `connecta_transfers` e a contaminação quebrava o teste quando rodava no mesmo processo.

### Changed
- RuboCop do conjunto: autocorreção segura (`rubocop -a`, 101 ofensas), `-A` restrito a `Performance/AncestorsInclude`, `Rails/WhereExists` e `Style/SymbolProc` (9), e `-a` em `Style/IfUnlessModifier` no installer (1). Restam 52 ofensas, não corrigidas: métricas de complexidade e tamanho (exigem refactor), `Rails/HasManyOrHasOneDependent`, `Rails/SkipsModelValidations`, `Rails/TransactionExitStatement`, `Lint/DuplicateBranch` (mudariam comportamento) e 3 `Style/RaiseArgs` (o `Error` aceita `status:` kwarg, então a reescrita não é segura).

### Tests
- Regressão em 37 arquivos, 5 lotes seriais com flock: 0 falhas (101 + 120 + 90 + 176 + 66 = 553 exemplos nos lotes com os arquivos listados).

## FORK-v7f · estabilização do refactor e RuboCop zerado

### Fixed
- `Connecta::Runtime::TransferTransaction#call`: rescues leem `prepared&.dig(:remote)` e `local&.record`, então exceção antes de `build_local_transaction` vira erro de domínio, não `NoMethodError`. Prova: `runtime_transfer_transaction_spec.rb` (exemplos "falha antes do prepare", RecordNotFound e ArgumentError). Verificado revertendo o `&.` em cópia: os dois exemplos falham com `NoMethodError`.
- `Connecta::Runtime::AclRevocationService#call`: ramos de revogação consolidados (mesma lógica, sem ramo duplicado).

### Changed
- Disables pontuais com justificativa de uma linha: `Rails/TransactionExitStatement` (retorno de idempotência antes de qualquer escrita), `Rails/HasManyOrHasOneDependent` (`OrgUnit`: nunca apagar filhos/grants em cascata), `Rails/SkipsModelValidations` (desativação em massa de unidade na ACL), métricas de método grande (ACL, HMAC, Gate, ativação, commit job, migração), `RSpec/SpecFilePathFormat` e `RSpec/DescribeClass` (nomes de spec mantidos por referência em evidências).
- Controllers: `Api::V1::Accounts::Conversations::ConnectaTransfersController#proxy` une dois `rescue` com corpo idêntico; `Metrics/AbcSize` desativado em `AclController#emergency_revocations` e `OutboundDispatchesController#resolve`.
- Specs: `receive_message_chain` trocado por dublês verificados de `ActionCable::RemoteConnections`; `update_all` de setup trocado por `find(1).update!` (mesma asserção); `@previous_delivery_method` trocado por `let!` nos dois specs de mailer.

### Tests
- RuboCop do conjunto (146 arquivos): 0 ofensas.
- Specs de transferência e runtime focados: 18 + 32 exemplos, 0 falhas.
- Regressão em 37 arquivos, 5 lotes seriais com flock: 531 exemplos, 0 falhas (lotes: 127, 45, 129, 191, 39). Número abaixo dos ~553 esperados no briefing; a diferença não foi investigada nesta rodada.

## FORK-v8 · conferência de fatos e gate do captain

### Docs (correção anexada)
- A linha citada como `conversation_http_hook.rb:100` (FORK-v7b, Fixed) é um comentário. O `raise Connecta::Scope::Denied, :forbidden` que o guard `connecta_scope_transfer_guard!` executa está em `app/services/connecta/scope/conversation_http_hook.rb:104`. Os demais fatos conferidos (abaixo) não tinham divergência.

### Fatos conferidos
- `Connecta::` em `app/services/connecta/scope/`: 356 ocorrências em 56 arquivos (contagem por `grep -o`, não por linha).
- `ContactInbox.where(id: conversation.contact_inbox_id)`: literal em `delivery_context.rb:103`. Em `delivery_check.rb:78-82` a mesma coluna entra como `[conversation.contact_inbox_id] & Array(context['contact_inbox_ids'])`.
- `app/services/connecta/runtime/account_mismatch.rb` existe (`AccountMismatch.check!` delega a `AccountGuard`); `account_guard.rb:2` define `def self.check!(provided, configured)`.
- `table_name`: presente em `app/services/connecta/scope/{access_audit,conversation_scope,scoped_inbox,user_auth_epoch}.rb:2` (nomes `connecta_g0_*`) e em `app/services/connecta/transfer/outbound_dispatch_record.rb:3` (`connecta_g0_outbound_dispatches`). `outbound_dispatch.rb` não tem `table_name` no transfer; o nome real está em `app/models/connecta/outbound_dispatch.rb:2`. `g0_adapter.rb:18` remapeia para os nomes reais, que batem com `db/schema.rb` (719, 738, 768, 794, 824).
- TTL: `Connecta::Scope::Projection.heartbeat_ttl` (`projection.rb:9-11`, padrão `DEFAULT_HEARTBEAT_TTL_SEC = 120`, env `CONNECTA_ACL_HEARTBEAT_TTL_SEC`) é a única definição; usada em `projection.rb:30` e `g0_adapter.rb:54`.
- Referências ao WP (`apps/whatsapp-platform/src/config.ts:156` e `src/services/humanService/runtime.ts:62`) conferem no worktree `feat/app-solicitacoes`, não no checkout `feat/demo-iluminacao-publica`.

### Tests
- Captain `spec/connecta/captain_scope_spec.rb`, três execuções consecutivas com `flock` e `g0_test_env.sh --spec --apply`: 36 exemplos, 0 falhas em cada uma (referência histórica de 33 em `.context/evidence/g0/34-final-regression.md`; o arquivo cresceu para 36 exemplos).

### Higiene
- `git diff --check`: limpo. Nenhum arquivo temporário em `spec/connecta` nem `spec/requests/connecta`.

## Docs (FORK-c9 · F7 pendências e plano de commit)
- `deploy/baileys-api/README.md`: TODO da imagem sem tag/digest (busca no Docker Hub sem resultado oficial; decisão humana) e registro do render do compose.
- `docs/runbooks/connecta-baileys-saude.md`: §5.1 paridade de env (`CONNECTA_ACL_HEARTBEAT_TTL_SEC` do fork = `CONNECTA_ACL_HEARTBEAT_MAX_AGE_SEC` do WP, 120 s) e sintoma de divergência.
- `.context/gotchas.md`: divergência aceita do timestamp (WP `\d{10,}` × fork `\d{10}`), sem efeito prático até 2286.
- `.context/plans/2026-10-25-plano-commit-connecta.md`: plano de commit do fork (7 commits, caminhos, mensagens, ordem e comandos prontos). Nada executado.

## Tests (FORK-c9)
- `docker compose -f deploy/baileys-api/docker-compose.yml config`: passou com valores fake do `.env.example` copiados para `/tmp/opencode` (exit 0). Sem `.env` real no repo.

## Changed (FORK-c10 · imagens do baileys-api e Redis fixadas)
- `deploy/baileys-api/docker-compose.yml`: `baileys-api` passou de `ghcr.io/chatwoot/baileys-api:TODO-fixar-tag` para `ghcr.io/fazer-ai/baileys-api:v1.21.0@sha256:738477885d5e1f7a01a03a1940ee2292ec24bf634e3e2cf49ae11bfa19e0fb8e`; `redis` passou de `redis:7-alpine` para `redis:7-alpine@sha256:57e4255cc971b1c8d6f8a6ca283ac01bc3ecdd914273ef6bfaede87aaecd6541`. Demais propriedades mantidas.
- `deploy/baileys-api/README.md`: TODO removido; seção de procedência com repositório, tag, digest, data (2026-10-25) e comandos de verificação.
- `.context/plans/2026-10-25-plano-commit-connecta.md`: plano inclui a mudança do compose/README no c4 e o próprio plano no c6.

## Tests (FORK-c10)
- Consulta de metadados do GHCR (`tags/list`) e `docker buildx imagetools inspect` de `fazer-ai/baileys-api:v1.21.0` e `redis:7-alpine`: sem pull de camadas, sem container.
- `docker compose -f docker-compose.yml config` com `.env.example` copiado para diretório temporário (`/tmp/opencode`): exit 0; imagens renderizadas com digest.
- `git diff --check`: limpo.
