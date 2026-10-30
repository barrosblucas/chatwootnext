# Evidência de implementação F3–F5 — fork Chatwootnext

Data: 2026-10-24. Escopo: código local de produto no fork. **Não é validação funcional nem aprovação do G0.**

## Implementado neste worktree

- F3: tabelas aditivas `connecta_*`, modelos de projeção, autorização por escopo, heartbeat fail-closed, revogação por epoch e retarget único de modelos G0 no boot opt-in.
- T4.1: entrada de recepção e ativação idempotente por versão; rota autenticada por HMAC.
- F5: resumo obrigatório com assunto, ações já feitas e próxima ação; despacho pendente/incerto retém a transferência; destino permanece `pending_activation` até confirmação; job confirma ao WP em `/attendance/v1/transfers/:id/activated` com retry.
- UI: seleção de destino, resumo, estado da transferência, vínculo de identidade e reconciliação de despacho; limpeza do cache em revogação ACL/socket.
- O HMAC usa `X-Connecta-Timestamp`, `X-Connecta-Signature: sha256=…` e `timestamp.METHOD.request-target.rawBody`; a query string é parte do request-target. Segredos são separados por direção.
- IDs de conversa externos são `display_id`; IDs locais das tabelas permanecem `Conversation.id`. A ativação procura pela conta configurada e pelo `display_id` exato.
- Runtime é opt-in via `CONNECTA_HUMAN_NUMBER_ENABLED=false` por padrão. O adapter não usa `eval`/`class_eval`, não altera globalmente ActiveRecord e não alterna tabela por requisição. No boot habilitado, os modelos G0 são retargetados uma vez para as tabelas de produto `connecta_*`; a migration não foi executada.
- A espera por despacho agora é `CONNECTA_DISPATCH_WAIT_MS` (0–30000 ms), padrão 5000 ms. O padrão preserva o comportamento anterior e não exige nova variável.

## Contratos coordenados

- Segredos: `CONNECTA_PLATFORM_TO_FORK_SECRET` e `CONNECTA_FORK_TO_PLATFORM_SECRET`.
- Destinos: `GET /attendance/v1/transfer-destinations?conversation_id=<display_id>`.
- Prepare envia protocolo/versão, UUID do setor, ator vindo de `Current.user`, hash e tamanho do resumo; o texto não sai do fork.
- Commit usa `destination_conversation_id=<display_id>`; após ativar localmente o job notifica `POST /attendance/v1/transfers/:id/activated` com `case_version`.

## Código de specs presente, validação pendente

- `spec/connecta/runtime_hmac_authenticator_spec.rb` cobre assinatura por método/path/body e janela de replay.
- `app/javascript/dashboard/components/buttons/specs/TransferActionSummary.spec.js` cobre campos e payload do resumo.
- Nenhuma spec, lint, build, migração ou aplicação foi executada nesta etapa. Não registrar esses casos como aprovados.
- G0 R1 permanece **REJEITADO**. RF1/RF3/RF6 e hooks RF2/RF4/RF5 são código existente/em revisão, não aprovação; revisão final do Juiz permanece pendente.

## Limites operacionais

F7/F8 não foram preparados nesta etapa. QR, pareamento, número real, E2E de homologação, execução de migrações e produção seguem pendentes de autorização específica. O roteiro de homologação T8.1 não foi executado.

## Anexo 2026-10-25 — CONTRATO DE FIO v1 (decisão do orquestrador) + correções 3a/3b/3c

Decisão [O] do orquestrador (2026-10-25). Conversas = `display_id` do Chatwoot.
Todo corpo/consulta carrega `account_id` (inteiro); o receptor recusa com 403 se
divergente da conta configurada (`CONNECTA_ACCOUNT_ID`). HMAC
`X-Connecta-Timestamp` + `X-Connecta-Signature: sha256=<hex>` sobre
`${ts}.${METHOD}.${path+query}.${rawBody}`, ±60s. Campos desconhecidos ignorados.

Fork→WP (`CONNECTA_FORK_TO_PLATFORM_SECRET`):

1. `GET /attendance/v1/transfer-destinations?account_id=&conversation_id=&actor_chatwoot_user_id=`
2. `POST /attendance/v1/transfers/prepare` (`transfer_id` uuid, `account_id`,
   `conversation_id`, `case_protocol`, `case_version`, `destination_org_unit_id` uuid,
   `actor_chatwoot_user_id`, `summary_sha256`, `summary_length`)
3. `POST /attendance/v1/transfers/:id/commit` (`account_id`,
   `destination_conversation_id`, `provider: "chatwoot"`, `committed_at` ISO8601)
4. `POST /attendance/v1/transfers/:id/abort` (`account_id`, `reason`) — o fork DEVE
   chamar quando a transação local falha/é desfeita após prepare bem-sucedido
   (antes nunca chamava); com retry via job novo `TransferAbortJob`
5. `POST /attendance/v1/transfers/:id/activated` (`account_id`, `case_version`)
6. `POST /attendance/v1/identity-links/confirm` (`account_id`, `chatwoot_user_id`, `code`)
7. `POST /attendance/v1/acl/emergency-revocations` (`account_id`, `chatwoot_user_id`,
   `actor_user_id`, `epoch`, `revocation_id`)

WP→fork (`CONNECTA_PLATFORM_TO_FORK_SECRET`):

8. `POST /connecta/v1/acl/sync` (`account_id`, `projection_version`, `events: []`) —
   também é heartbeat (events vazio renova o heartbeat da ACL; sem heartbeat no
   limite → fail-closed, já existente)
9. `POST /connecta/v1/acl/revoke` (`account_id`, `chatwoot_user_id`, `epoch`,
   `revocation_id`) → 200 `{ack:{epoch}, revocation_id}`
10. `POST /connecta/v1/scopes/:display_id/activate` (`account_id`, `expected_state`,
    `org_unit_id`, `case_protocol`, `session_ref`, `case_version`)
11. `GET /connecta/v1/transfers/:id?account_id=`

Decisões [O]: ingresso da recepção pelo webhook de conta Chatwoot (sem
`/attendance/v1/agent-bot`); ACL push + heartbeat (sem pull de snapshot).

### Correções aplicadas

- 3a (`scope/gate.rb`, `scope/delivery_check.rb`): `scope_readable?` era privado mas
  `delivery_check` (contato excluído) chamava com receptor explícito → `NoMethodError`.
  O Gate agora expõe `readable_scope?` (mesma regra, só para esse chamador); o
  privado continua privado.
- 3b (`runtime/acl_revocation_service.rb`): epoch igual com registro ainda ativo
  devolvia ack sem revogar. Agora ack só ocorre com barreira local efetiva
  (revoga + broadcast + desconexão); revogação já aplicada é idempotente (ack sem
  reescrever nem rebroadcast); epoch menor não rebaixa nem reativa.
- 3c (`runtime/reception_scope_creator.rb`, `runtime/installer.rb`): sem unidade de
  recepção configurada o criador só logava e omitia o escopo (fail-closed
  silencioso). Agora levanta `MissingReceptionUnit` (explícito/reconciliável) e o
  boot valida quando há inbox marcada.

### Specs runtime escritas (NÃO executadas)

Padrão G0 (`spec/connecta/support/*` + `spec/support/connecta/g0_target_guard.rb`).
Nenhuma spec, lint, build, migração ou aplicação foi executada nesta etapa.

- `spec/connecta/runtime_platform_client_contract_spec.rb` — corpos/paths 1–7 com
  `account_id`; `actor_chatwoot_user_id` no destino; `committed_at` no commit;
  abort em falha local pós-prepare; `case_version` no activated; retry do abort.
- `spec/connecta/runtime_acl_sync_spec.rb` — heartbeat com `events: []`; versão
  velha ignorada sem renovar heartbeat; `account_id` divergente/ausente → 403.
- `spec/connecta/runtime_acl_revocation_spec.rb` — epoch igual + ativo só dá ack
  após barreira; epoch maior revoga; já revogado é idempotente; epoch menor não
  rebaixa; account divergente → 403.
- `spec/connecta/runtime_scope_activation_spec.rb` — `display_id`, `account_id`,
  409 de divergência, `expected_state`, idempotência.
- `spec/connecta/runtime_transfer_transaction_spec.rb` — prepare→commit→activated;
  falha local pós-prepare ⇒ job de abort com retry; transporte ⇒ `unknown`;
  prepare recusado ⇒ sem abort remoto.
- `spec/connecta/runtime_reception_scope_spec.rb` — escopo `reception` criado; sem
  unidade configurada falha explícita; boot valida com inbox marcada.
- `spec/connecta/scope_gate_delivery_contact_deleted_spec.rb` — regressão do
  defeito 3a (wrapper público, entrega inclui/exclui, admin fora).

## Anexo T3.9 — contenção (código pronto, NÃO validado funcionalmente)

- Migration aditiva `20261024000001`: coluna `enforcement` (default
  `enforce`, NOT NULL) de forma idempotente sobre `connecta_scoped_inboxes`.
- Gate: `admin_only` nega escrita/leitura a não-admin em todas as superfícies
  que passam pelo Gate (policy, lista, socket, anexo, contato, busca);
  `maintenance` bloqueia escrita humana (inclusive claim de despacho vira
  `parked`); leitura segue a regra normal. Admin permitido com auditoria.
- Superfície de envio: `conversation_http_hook.write_guard!` traduz manutenção
  em 409 (`Denied :conflict`) antes do team_id; `SendReplyHook`/claim mantém o
  ponto único existente sem caminho paralelo.
- Rota admin `PATCH /api/v1/accounts/:id/connecta/scoped_inboxes/:inbox_id`
  alterna o `enforcement` com auditoria; não-admin recebe 403
  (`rescue Pundit::NotAuthorizedError`, mesmo padrão dos demais controllers
  Connecta). Nenhuma spec executada nesta tarefa.
