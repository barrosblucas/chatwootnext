# Arquitetura — chatwootnext

Fronteiras, componentes e decisões técnicas principais. Decisão individual fica em `decisions/`.
Fatos verificados no código; `TODO` = ainda não confirmado.

## Visão geral
Chatwoot (fork `fazer-ai/chatwoot`) em Rails 7.1 com frontend Vue 3 em `app/javascript/`. Overlay Enterprise em `enterprise/`. Jobs assíncronos em Sidekiq (`config/sidekiq.yml`), com PostgreSQL para dados e Redis para Sidekiq e ActionCable (`config/initializers/actioncable.rb`).

## Componentes
| Componente | Pasta | Responsabilidade | Depende de |
|---|---|---|---|
| Backend Rails | `app/`, `config/routes.rb` | Controllers de API (`api/v1`, `api/v2`), models, services | PostgreSQL, Redis |
| Enterprise | `enterprise/` | Extensões por módulo (`prepend_mod_with`), não por edição do OSS (`AGENTS.md`) | `app/` |
| Frontend | `app/javascript/` | SPA Vue (entrypoints: `dashboard.js`, `widget.js`, `portal.js`, etc.) | API REST |
| Jobs | `config/sidekiq.yml`, `app/jobs/` | Processamento assíncrono | Redis, PostgreSQL |
| Banco | `db/` | Migrações (`db/migrate/`) e `db/schema.rb` | PostgreSQL |
| Transferência Connecta | `app/services/connecta/transfer_service.rb` | Transferência atual, mediada (não é a transação local do plano Baileys) | conversas |

## Fronteiras
- Rotas da API de conta ficam em `config/routes.rb` sob `api/v1/accounts/*` e `api/v2/accounts/*`; controllers em `app/controllers/` e, para Enterprise, em `enterprise/app/controllers/`.
- Entrada: strong params (`CLAUDE.md`). Saída: contrato OpenAPI em `swagger/swagger.json`, validado com Skooma nas specs de request (`spec/rails_helper.rb:84-86`).
- Rotas SPA: `/app/*params` cai em `dashboard#index` (`config/routes.rb:20`), antes das rotas explícitas de `/app/...`; ver `gotchas.md`.

## Dados e integrações
- Banco: PostgreSQL configurado por `config/database.yml`, que lê `POSTGRES_*` do ambiente. Migrações em `db/migrate/`, schema em `db/schema.rb`.
- Integrações externas expostas como rotas em `config/routes.rb` (Slack, Shopify, Linear, Notion, Dyte, Twitter, Microsoft, Google, Instagram, TikTok, WhatsApp). Clientes e workers: TODO: mapear por integração.

## Decisões técnicas vigentes
- Assinatura textual de nome — SOMENTE provider Baileys, USER LATEST (2026-11-03, release ensaio `8f2b...` ativo): `MessageBuilder#prepend_baileys_agent_name` usa `**_Nome_**:` (fio `*_Nome_*: ` negrito+itálico WhatsApp) sob `channel_whatsapp_signature_enabled`, idempotente ao novo e normaliza 1x os legados `*_nome_*: ` e `*nome*:` do mesmo remetente; `editorHelper.js` espelha no frontend; `Channel::Api` mantém `*Nome*:`; detalhe em `.context/changelog/CHANGELOG_2026_11_03.md`.
- Realtime de mídia marcada + envelope destinations (2026-11-03, release ensaio `8f2b...` ativo): `media_broadcast_sanitizer` + `broadcast_job_guard` + `action_cable_listener` sanitizam `data_url`/`thumb_url` com marcador `connecta_media_resolve` (fail-closed); frontend `connectaMediaRehydrate` resolve por viewer via GET; `connecta_transfers_controller#transfer_destinations_list` expõe só array `{ destinations: [...] }`; `INTERNAL_HOST_URL=http://rails:3000` + `BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL=true` preservados em rails/sidekiq com `FRONTEND_URL=https://192.168.1.32:3443`; detalhe em `.context/changelog/CHANGELOG_2026_11_03.md`.
- Demais decisões em `decisions/` (formato ADR-lite; regra de nomenclatura no `README.md`).
- HTTPS só no ensaio LAN (2026-11-02, runtime de teste, sem produção): proxy `tls-proxy` (Caddy oficial 2.11.7, tag+digest fixados) publica apenas `192.168.1.32:3443→rails:3000` e `:3444→painel Saude:6700`; `FRONTEND_URL=https://192.168.1.32:3443` em rails+sidekiq, `FORCE_SSL` false, HTTP legado intacto; CA local SAN-IP em `deploy/ensaio-tls/certs/` (ignorado, 0700/0600); decisão 006.

## Protocolo no Chatwoot — busca, lista e visão por etapas (2026-11-08, código; CI pendente)
- `Connecta::Scope::ProtocolSearch` busca `connecta_conversation_scopes.case_protocol` somente sobre relação já escopada; `ConversationFinderHook#filter_by_query` e `SearchHook#filter_conversations` fazem OR com a busca de mensagem, com wildcard literal e limite de 60.
- `GET /api/v1/accounts/:account_id/connecta/conversations/metadata?ids=...` devolve, em lote, `case_protocol`, `state`, `org_unit_name` e `root_unit_name` apenas das conversas visíveis (máx. 50 ids; ocultos são omitidos).
- `GET /api/v1/accounts/:account_id/connecta/protocols/:protocol` devolve etapas visíveis ao ator, ordenadas, cada uma após `Gate#read?` (`protocol_view`, auditado). Admin nativo vê a conta inteira; agente vê só etapas autorizadas; `admin_nominal` mantém a leitura auditada do `Gate`, sem ganhar escrita; `transferir` sozinho não lê. Protocolo inválido/inexistente/sem etapa visível = 404 genérico. Payload só tem metadados/links de etapa, nunca contato/telefone.
- Lista: `connectaMetadata` (Vuex) busca o lote quando a lista muda; `ConversationCard`/`ConversationCardExpanded` exibem `Raiz | Setor | Atendente` dinâmico, preservando o nome do contato e `aria-label`. Transferência nova entra pelo watcher; assignee usa o evento nativo.
- Chip/drawer: `ConnectaConversationStatus` mostra o protocolo e `ConnectaProtocolDrawer` lista somente as etapas retornadas pelo endpoint.
- `ComposeConversation` renderiza `ConnectaSectorPicker` (com os destinos já carregados), corrigindo o fluxo >1 setor.
- Nota privada de destino em `LocalTransaction#open_destination` é genérica, sem nome/id/link da origem; a navegação condicional é do endpoint.
- Decisão 005 comprovada no caminho real de ingestão Baileys (`incoming_after_resolved_spec.rb`): conversa resolvida com escopo `closed` não recebe o próximo inbound; com `inbox.lock_to_single_conversation=false`, o fluxo nativo cria conversa nova, novo `display_id` e escopo `reception` na mesma inbox/contato; retry do `source_id` antigo não duplica. **Requisito runtime do operador:** a inbox do número humano precisa de `lock_to_single_conversation=false`; com `true`, o fluxo nativo reutiliza a conversa resolvida e o hook apenas bloqueia a reabertura, deixando a mensagem na conversa terminal.
- Sem migração; decisão em `decisions/007-protocolo-busca-visao-etapas.md` e changelog do dia.
