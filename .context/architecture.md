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
| Vínculo Connecta (usuários) | `app/controllers/connecta/v1/users_controller.rb` + `app/services/connecta/provisioning/agent_provisioner.rb` | Fase 1: WP provisiona/troca senha/desativa agente via HMAC (sempre `agent`, nunca `administrator`); privilegiado existente (SuperAdmin ou admin em qualquer conta) = 409 `not_agent` nos 3 endpoints sem nada mudar; `set_password` com senha rejeitada pelo Devise = 422 `invalid_password`; reativar = provisionar de novo; detalhe em `.context/changelog/CHANGELOG_2026_11_10.md` | plataforma WP |
| CSAT Fase 2 (protocolo) | `app/services/connecta/scope/csat_policy.rb` + `app/jobs/connecta/runtime/csat_push_job.rb` | Inbox marcada só pesquisa a resolução final do protocolo (não origem `transferred_out`, não triagem); texto whatsapp aprovado com protocolo + escala 1–5 em emojis (`{{protocolo}}` configurável; modo link intacto); `disable_feedback` esconde/ignora comentário; nota espelhada no WP via `POST /attendance/v1/csat` (HMAC fork→plataforma) com `assigned_agent_id` + `assigned_agent_name` (null-safe; sem PII/contato/comentário); Resolver em conversa escopada remove da lista/store e volta à lista (frontend-only: `dashboard/helper/connectaResolveLeave.js`, sem `scope.revoked`/unassign); senha de agente gerenciado bloqueada no forgot/reset/profile (`PasswordGuard`), admins intactos; detalhe em `.context/changelog/CHANGELOG_2026_11_10.md` e `CHANGELOG_2026_11_11.md` | plataforma WP |
| Opt-out do bot Etapa 3 | `connecta_bot_optouts_controller.rb` + `connecta/v1/contacts_controller.rb` + menu de contexto | Item "Desativar/Reativar bot neste número" no menu da conversa (só caixa humana, estado sob demanda); fork→WP `POST/GET /attendance/v1/bot-optout` (autoridade) + espelho local `contact.custom_attributes['connecta_bot_disabled']`; WP→fork HMAC `POST /connecta/v1/contacts/bot_optout`; CSAT pula número com flag; selo no cabeçalho; detalhe em `.context/changelog/CHANGELOG_2026_11_11.md` | plataforma WP |

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
- `GET /api/v1/accounts/:account_id/connecta/protocols/:protocol?cursor=...&limit=...` devolve etapas visíveis ao ator, ordenadas por `(created_at,id)`, cada uma após `Gate#read?` (`protocol_view`, auditado); o cursor é opaco e o Gate roda antes do corte da página. Admin nativo vê a conta inteira; agente vê só etapas autorizadas; `admin_nominal` não enumera `transferred_out` no endpoint, sem ganhar escrita nem alterar o `Gate` global; `transferir` sozinho não lê. Protocolo inválido/inexistente/sem etapa visível = 404 genérico. Payload só tem metadados/links de etapa, nunca contato/telefone.
- Lista: `connectaMetadata` (Vuex) busca o lote quando a lista muda; `ConversationCard`/`ConversationCardExpanded` exibem `Raiz | Setor | Atendente` dinâmico, preservando o nome do contato e `aria-label`. Transferência nova entra pelo watcher; assignee usa o evento nativo.
- Chip/drawer: `ConnectaConversationStatus` mostra o protocolo e `ConnectaProtocolDrawer` lista somente as etapas retornadas pelo endpoint.
- `ComposeConversation` renderiza `ConnectaSectorPicker` (com os destinos já carregados), corrigindo o fluxo >1 setor.
- Nota privada de destino em `LocalTransaction#open_destination` é genérica, sem nome/id/link da origem; a navegação condicional é do endpoint.
- Decisão 005 comprovada no caminho real de ingestão Baileys (`incoming_after_resolved_spec.rb`): conversa resolvida com escopo `closed` não recebe o próximo inbound; com `inbox.lock_to_single_conversation=false`, o fluxo nativo cria conversa nova, novo `display_id` e escopo `reception` na mesma inbox/contato; retry do `source_id` antigo não duplica. **Requisito runtime do operador:** a inbox do número humano precisa de `lock_to_single_conversation=false`; com `true`, o fluxo nativo reutiliza a conversa resolvida e o hook apenas bloqueia a reabertura, deixando a mensagem na conversa terminal.
- Sem migração; decisão em `decisions/007-protocolo-busca-visao-etapas.md` e changelog do dia.

## ACL do vínculo — robustez fork-side (2026-11-09, código; CI pendente)
- Lápide de grant (B3): `connecta_user_grants.grant_id` (uuid do `staff_grant` do WP, anulável) + `connecta_revoked_grants(grant_id PK, revoked_at)`; `grant.revoke` com `grant_id` apaga a linha e grava a lápide, `grant.upsert` com `grant_id` lapidado é no-op; sem `grant_id`, comportamento legado (compatível com WP `c47dd1c`).
- Lápide de trinca (2026-11-10, código; CI pendente): `connecta_revoked_grants` também guarda a trinca (`user_id`, `org_unit_id`, `permission`); `grant.revoke` com `grant_id` + trinca completa lapida a trinca; `grant.upsert` legado (sem `grant_id`) de trinca lapidada é ignorado; `grant.upsert` com `grant_id` novo aplica e limpa só a trinca (lápides por `grant_id` antigo seguem valendo); revoke só com `grant_id` (sem trinca) não lapida trinca. Detalhe em `.context/changelog/CHANGELOG_2026_11_10.md`.
- Foto no re-vínculo (Q7.5): `link.upsert` com `active_grant_ids` apaga grants do usuário fora da lista ou legados (sem `grant_id`); sem a lista, nada muda; evento com epoch velho não aplica a foto.
- Graça de heartbeat (B5): `CONNECTA_ACL_STALE_GRACE_SEC` (padrão 900 s; `0` desliga) — entre TTL e TTL+graça, `Projection#usable?` mantém a leitura com os últimos grants (`Gate` + lista usam a mesma decisão; já-revogado continua negado; modo degradado gera `Rails.logger.warn`); depois, fail-closed. `TransferPolicy`/`can_transfer?` seguem fail-closed no TTL.
- Cursor de protocolo (B15): a página que enche exatamente na cauda de um lote cheio mantém cursor no último item visível; só lote curto totalmente consumido prova exaustão.
- Env documentada em `.env.example` (`CONNECTA_ACL_HEARTBEAT_TTL_SEC`, `CONNECTA_ACL_STALE_GRACE_SEC`) e `docs/runbooks/connecta-baileys-saude.md` §5.1b; detalhe em `.context/changelog/CHANGELOG_2026_11_09.md`.
