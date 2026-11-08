# Changelog 2026-11-08

## Protocolo no Chatwoot — busca, identificação na lista e visão por etapas

### Contexto
A transferência humana cria uma conversa nova na mesma inbox e mantém o mesmo protocolo. O Chatwoot não tinha busca por protocolo (a busca nativa cobre somente conteúdo de mensagem), a lista não mostrava o setor autorizado e não havia uma visão única das etapas. O modal de setor da admissão manual existia, mas não estava importado/renderizado no `ComposeConversation`; com mais de um setor elegível o fluxo parava sem admitir.

### Mudanças
- `Connecta::Scope::ProtocolSearch`: busca literal (wildcards escapados, limite de 60) sobre uma relação já escopada; usada na busca global e na busca da lista.
- `Connecta::Scope::ConversationFinderHook#filter_by_query`: OR entre conteúdo de mensagem e protocolo, sem ampliar a relação entregue pelo `ConversationQuery`.
- `Connecta::Scope::ConversationMetadata` + `Connecta::Scope::ConversationMetadataController`: metadados em lote (`raiz`, `setor`, `protocolo`) somente para conversas visíveis; ids ocultos são omitidos.
- `Connecta::Scope::ProtocolView` + `Connecta::Scope::ProtocolsController`: etapas ordenadas do protocolo, cada uma passando pelo `Gate` (`protocol_view`); admin nativo vê a cadeia inteira, agente vê só as etapas autorizadas, `admin_nominal` não enumera `transferred_out` e `transferir` não lê. Resposta omite id/nome/link de etapa oculta e não serializa contato/telefone.
- Lista: rótulo dinâmico `Raiz | Setor | Atendente` (sem hardcode), mantendo o nome do contato e `aria-label`; metadados são buscados em lote quando a lista muda (transferência cria conversa nova; assignee usa o meta nativo).
- Chip/drawer `ConnectaProtocolDrawer`: protocolo visível no topo da conversa, etapas com links condicionais fornecidos pelo endpoint; sem conteúdo de transcript adicional.
- `ComposeConversation.vue`: `ConnectaSectorPicker` importado/renderizado, recebendo os destinos já carregados e o `idempotencyKey`; o modal abre para >1 setor e a admissão usa o endpoint dedicado.
- `LocalTransaction#open_destination`: nota privada do destino passou a ser genérica (`Atendimento transferido · protocolo …`), sem nome/id/link do setor de origem. A navegação condicional fica no protocol view.
- i18n `en`, `pt_BR`, `es`: `CONNECTA.PROTOCOL.*` e `CONNECTA.MANUAL_ADMISSION.*`.

### Contrato
- `GET /api/v1/accounts/:account_id/connecta/conversations/metadata?ids=1,2`
  - `200 { conversations: { "<display_id>": { case_protocol, state, org_unit_name, root_unit_name } } }`
  - ids inválidos ou >50: `422 invalid_ids`; ids ocultos/inexistentes: omitidos.
- `GET /api/v1/accounts/:account_id/connecta/protocols/:protocol`
  - `200 { protocol, stages: [{ conversation_id, status, state, root_unit_name, org_unit_name, assignee_name, started_at, updated_at }] }`
  - protocolo inválido, inexistente ou sem etapa visível: `404` genérico.
- Nenhum campo de cidadão, telefone, CPF ou hash.

### Privacidade / ACL
- Toda busca/metadado/visão parte de `Current.account` e de relação escopada; não há lookup global de protocolo.
- Protocol view aplica `Connecta::Scope::Gate#read?` por etapa, com auditoria `connecta_access_audits`.
- Admin nativo mantém acesso total same-account; `admin_nominal` não enumera `transferred_out` no endpoint de protocolo (sem alterar o `Gate` global) e não ganha escrita; agente só vê etapas em `READ_STATES` e no caminho de grants `acompanhar`/`atender`.
- Nota privada não revela etapa de origem; links só pelo endpoint condicional.

### Validação
- Specs novos/ajustados: `spec/connecta/protocol_view_spec.rb` (endpoint, metadados, busca, wildcard, cross-account, agente A/B, admin nativo, admin nominal, transferir-só), `spec/connecta/transfer_cutover_spec.rb` (mesma inbox com ids sintéticos distintos; nota sem setor de origem), `spec/connecta/incoming_after_resolved_spec.rb` (ingestão Baileys real: resolvida → nova conversa/escopo reception na mesma inbox/contato; retry antigo idempotente; nova mensagem não cai na conversa antiga).
- Frontend: helper `connectaLabel.spec.js`, `ConversationCard` (rótulo e contato), `ConnectaProtocolDrawer` (somente etapas devolvidas, link, vazio/erro), `ConnectaSectorPicker` (admissão/erro), wiring estático do modal no Compose.
- Gates de Rails/frontend e build ficam para GitHub Actions; sem Ruby local, sem banco/serviço de produção e sem build local nesta entrega.
- `git diff --check` local; i18n `fork_translations.rb check` no CI.

### Limpeza operacional interna
- `Connecta::Purge::Cleanup`: classe interna de manutenção (sem rota HTTP/permissão nova), com `plan(account_ids:)`, `apply(account_ids:, expected_hash:, confirmation:, writers_stopped:)` e `purge_blobs(blob_ids:)`. O `apply` revalida hash/contagens antes de deletar, roda mensagens/conversas/escopos em transação, verifica preservação de contatos/ContactInbox/contas/inboxes/usuários/account_users/config e só purga ActiveStorage depois do commit; falha de arquivo retorna `committed_blob_pending` com os ids exatos para retry.
- `Connecta::Purge::SidekiqCleanup`: `plan`/`apply` do dead set com hash de contagens + digests por entrada; preserva scheduled/retry e `ActiveStorage::PurgeJob`; só remove `Webhooks::WhatsappEventsJob` quando classe, digests e contagens batem. Nenhum arg/payload é impresso.
- Specs sintéticas: `spec/connecta/purge_cleanup_spec.rb` (sucesso, nova conversa/rowcount antes do delete, rollback, purge após commit com retry, writers/confirmação) e `spec/connecta/purge_sidekiq_cleanup_spec.rb` (dead alvo, alvo tardio, classe desconhecida, data ingress em retry, confirmação). O wrapper privado do operador deve chamar estas classes da imagem final, sem copiar lógica.
- Contrato do wrapper privado: `Connecta::Purge::Cleanup.plan(account_ids: [...])` retorna `inventory_hash`; `apply(account_ids: [...], expected_hash: hash, confirmation: "APPLY:#{hash}", writers_stopped: true)` revalida e executa; se `status == "committed_blob_pending"`, repetir `purge_blobs(blob_ids: result[:remaining_blob_ids])`. No Sidekiq: `Connecta::Purge::SidekiqCleanup.plan(keys: ...)` e `apply(expected_hash:, confirmation:, writers_stopped:, keys:)`. Nenhum dos dois aceita default de conta/hash.

### Fora do escopo / pendências
- `fdb8190` (Conecta) continua sendo o caminho de borda de novo ciclo na mesma conversa; a regra canônica de novo pedido em conversa nova é do ciclo de resolução do Chatwoot. Não alterado neste repo; a proteção de `reception` e a colisão `23505` pertencem ao outro autor. O ciclo completo NÃO é declarado validado só porque o WP silencia a conversa antiga.
- O gate Chatwoot cobre: conversa resolvida não recebe inbound; `lock_to_single_conversation=false` cria conversa nova/escopo reception; retry antigo idempotente. O requisito de runtime (inbox humana com a flag false) é operacional e precisa ser confirmado no ambiente.
- Sem migração: `case_protocol`, `org_unit_id`, `transfer_id` e assignee nativo já existem. Índice de protocolo, se necessário, exige migração aditiva separada.
