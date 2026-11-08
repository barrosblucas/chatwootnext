# Changelog 2026-11-08

## Protocolo no Chatwoot — busca, identificação na lista e visão por etapas

### Contexto
A transferência humana cria uma conversa nova na mesma inbox e mantém o mesmo protocolo. O Chatwoot não tinha busca por protocolo (a busca nativa cobre somente conteúdo de mensagem), a lista não mostrava o setor autorizado e não havia uma visão única das etapas. O modal de setor da admissão manual existia, mas não estava importado/renderizado no `ComposeConversation`; com mais de um setor elegível o fluxo parava sem admitir.

### Mudanças
- `Connecta::Scope::ProtocolSearch`: busca literal (wildcards escapados, limite de 60) sobre uma relação já escopada; usada na busca global e na busca da lista.
- `Connecta::Scope::ConversationFinderHook#filter_by_query`: OR entre conteúdo de mensagem e protocolo, sem ampliar a relação entregue pelo `ConversationQuery`.
- `Connecta::Scope::ConversationMetadata` + `Connecta::Scope::ConversationMetadataController`: metadados em lote (`raiz`, `setor`, `protocolo`) somente para conversas visíveis; ids ocultos são omitidos.
- `Connecta::Scope::ProtocolView` + `Connecta::Scope::ProtocolsController`: etapas ordenadas do protocolo, cada uma passando pelo `Gate` (`protocol_view`); admin nativo vê a cadeia inteira, agente vê só as etapas autorizadas, `admin_nominal` não enumera `transferred_out` e `transferir` não lê. Paginação cursor `(created_at,id)` account-bound, Gate antes do corte da página, `next_cursor` opaco e drawer com “Carregar mais” (admin nativo carrega todas as páginas). 201+ etapas do admin nativo são paginadas sem perder/repetir, a página final vazia responde `200` e cursor/limit inválidos respondem `422`. Resposta omite id/nome/link de etapa oculta e não serializa contato/telefone.
- Lista: rótulo dinâmico `Raiz | Setor | Atendente` (sem hardcode), mantendo o nome do contato e `aria-label`; metadados são buscados em lote quando a lista muda (transferência cria conversa nova; assignee usa o meta nativo).
- Cache de metadados `connectaMetadata`: escopo conta/ator/epoch, TTL de 5 min, lotes de 50, `refresh` imediato em reuso/transferência e timer de 60 s que só rebusca entradas vencidas, com cleanup no unmount.
- Chip/drawer `ConnectaProtocolDrawer`: protocolo visível no topo da conversa, etapas com links condicionais fornecidos pelo endpoint; sem conteúdo de transcript adicional.
- `ComposeConversation.vue`: `ConnectaSectorPicker` importado/renderizado, recebendo os destinos já carregados e o `idempotencyKey`; o modal abre para >1 setor e a admissão usa o endpoint dedicado.
- `LocalTransaction#open_destination`: nota privada do destino passou a ser genérica (`Atendimento transferido · protocolo …`), sem nome/id/link do setor de origem. A navegação condicional fica no protocol view.
- i18n `en`, `pt_BR`, `es`: `CONNECTA.PROTOCOL.*` e `CONNECTA.MANUAL_ADMISSION.*`.

### Contrato
- `GET /api/v1/accounts/:account_id/connecta/conversations/metadata?ids=1,2`
  - `200 { conversations: { "<display_id>": { case_protocol, state, org_unit_name, root_unit_name } } }`
  - ids inválidos ou >50: `422 invalid_ids`; ids ocultos/inexistentes: omitidos.
- `GET /api/v1/accounts/:account_id/connecta/protocols/:protocol?cursor=...&limit=...`
  - `200 { protocol, native_admin, stages: [{ conversation_id, status, state, root_unit_name, org_unit_name, assignee_name, started_at, updated_at }], next_cursor }`
  - `limit` 1..100 (padrão 50); `next_cursor` opaco continua a partir de `(created_at,id)`; página seguinte sem etapa visível devolve `200` com `stages: []` e `next_cursor: null`.
  - protocolo inválido, inexistente na primeira página ou cursor/limit inválido: `404`/`422` genéricos.
- Nenhum campo de cidadão, telefone, CPF ou hash.

### Privacidade / ACL
- Toda busca/metadado/visão parte de `Current.account` e de relação escopada; não há lookup global de protocolo.
- Protocol view aplica `Connecta::Scope::Gate#read?` por etapa, com auditoria `connecta_access_audits`.
- Admin nativo mantém acesso total same-account; `admin_nominal` não enumera `transferred_out` no endpoint de protocolo (sem alterar o `Gate` global) e não ganha escrita; agente só vê etapas em `READ_STATES` e no caminho de grants `acompanhar`/`atender`.
- Nota privada não revela etapa de origem; links só pelo endpoint condicional.
- Anexos de acompanhamento (2º+) usam `content_attributes.connecta_followup_nonce` no endpoint nativo de mensagens; retry do mesmo anexo devolve a mensagem existente (hook `FollowUpDedupeHook`), sem fila fictícia. O hook compara somente objetos decodificados (normal ou serializado legado), ignorando com segurança escalar/null/array/string, e o Compose repete uma vez o mesmo pending/echo_id+nonce antes de preservar o draft para retry.
- Caminho nativo (WhatsApp não-Baileys): `runNativeConversation` separa create/primeira mensagem da fila de anexos. Falha parcial mantém a conversa/id e os anexos pendentes com banner “Reenviar anexos” + link; o retry envia só a fila com os índices/nonces originais e nunca repete create nem a primeira mensagem. Sucesso total mantém o roteamento/form clear anteriores; Baileys segue com o mesmo nonce.

### Validação
- Specs novos/ajustados: `spec/connecta/protocol_view_spec.rb` (endpoint, metadados, busca, wildcard, cross-account, agente A/B, admin nativo, admin nominal, transferir-só), `spec/connecta/transfer_cutover_spec.rb` (mesma inbox com ids sintéticos distintos; nota sem setor de origem), `spec/connecta/incoming_after_resolved_spec.rb` (ingestão Baileys real: resolvida → nova conversa/escopo reception na mesma inbox/contato; retry antigo idempotente; nova mensagem não cai na conversa antiga).
- Frontend: helper `connectaLabel.spec.js`, `ConversationCard` (rótulo e contato), `ConnectaProtocolDrawer` (somente etapas devolvidas, link, vazio/erro e auto-load de várias páginas no admin nativo), `ConnectaSectorPicker` (admissão/erro), wiring do modal no Compose, retry de follow-up com o mesmo pending/nonce, parcial nativo (`runNativeConversation`/`sendFollowUpBatch`, create 1x, só pendentes) e timer de metadados com cleanup.
- Backend P2: `follow_up_dedupe_spec` (objeto, serializado legado e escalares/null/array/string), `protocol_view_spec` (205 etapas do admin nativo, página final vazia, cursor/limit inválidos), `incoming_after_resolved_spec` (unknown com ref dentro do IncomingHook, rollback sem job), `cleanup_spec` (rollback depois de `Conversation#destroy!` sem `ActiveStorage::PurgeJob`).
- Gates de Rails/frontend e build ficam para GitHub Actions; sem Ruby local, sem banco/serviço de produção e sem build local nesta entrega.
- `git diff --check` local; i18n `fork_translations.rb check` no CI.

### Limpeza operacional interna
- `Connecta::Purge::Cleanup`: classe interna de manutenção (sem rota HTTP/permissão nova), com `plan(account_ids:)`, `apply(account_ids:, expected_hash:, confirmation:, writers_stopped:)` e `purge_blobs(blobs:)` por manifesto opaco `{id,key,service_name}`. O `apply` revalida hash/contagens antes de deletar, roda mensagens/conversas/escopos em transação, inclui anexos de `ScheduledMessage`/`RecurringScheduledMessage`, verifica preservação de contatos/ContactInbox/contas/inboxes/usuários/account_users/installation_configs e só toca o storage depois do commit; falha real de `service.delete` retorna `committed_blob_pending` com o manifesto exato para retry, inclusive se a row do Blob já sumiu. O rollback depois de `Conversation#destroy!` não enfileira `ActiveStorage::PurgeJob` e preserva arquivos/rows agendados; a aplicação seguinte remove tudo pós-commit.
- `Connecta::Purge::SidekiqCleanup`: `plan(redis:, keys:)`/`apply(..., redis:, keys:)` do dead set, sem defaults de Redis/keys, com hash de contagens + digests por entrada; preserva scheduled/retry e `ActiveStorage::PurgeJob`; só remove `Webhooks::WhatsappEventsJob` quando classe, digests e contagens batem. Nenhum arg/payload é impresso.
- Specs sintéticas: `spec/connecta/purge/cleanup_spec.rb` (sucesso com anexos de mensagem e agendados, manifestos, nova conversa/rowcount/installation_config antes do delete, lista protegida/auditada imutável, anexo tardio aborta antes do commit, rollback sem enfileirar purge, purge após commit com retry por manifesto e arquivo ausente) e `spec/connecta/purge/sidekiq_cleanup_spec.rb` (dead alvo, alvo tardio, classe desconhecida, data ingress em retry, Redis/keys obrigatórios, confirmação). O wrapper privado do operador deve chamar estas classes da imagem final, sem copiar lógica.
- Contrato do wrapper privado: `Connecta::Purge::Cleanup.plan(account_ids: [...])` retorna `inventory_hash`; `apply(account_ids: [...], expected_hash: hash, confirmation: "APPLY:#{hash}", writers_stopped: true)` revalida e executa; se `status == "committed_blob_pending"`, repetir `purge_blobs(blobs: result[:remaining_blobs])`. No Sidekiq: `Connecta::Purge::SidekiqCleanup.plan(redis: <conexão>, keys: {schedule:, retry:, dead:})` e `apply(expected_hash:, confirmation:, writers_stopped:, redis:, keys:)`. Nenhum dos dois aceita default de conta/hash/Redis/keys.

### Fora do escopo / pendências
- `fdb8190` (Conecta) continua sendo o caminho de borda de novo ciclo na mesma conversa; a regra canônica de novo pedido em conversa nova é do ciclo de resolução do Chatwoot. Não alterado neste repo; a proteção de `reception` e a colisão `23505` pertencem ao outro autor. O ciclo completo NÃO é declarado validado só porque o WP silencia a conversa antiga.
- O gate Chatwoot cobre: conversa resolvida não recebe inbound; `lock_to_single_conversation=false` cria conversa nova/escopo reception; retry antigo idempotente. O requisito de runtime (inbox humana com a flag false) é operacional e precisa ser confirmado no ambiente.
- Sem migração: `case_protocol`, `org_unit_id`, `transfer_id` e assignee nativo já existem. Índice de protocolo, se necessário, exige migração aditiva separada.
