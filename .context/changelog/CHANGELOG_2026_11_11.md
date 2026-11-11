# Changelog 2026-11-11

## Etapa 3 · opt-out do bot por número (código; CI pendente)

- Base: `09439f11` (main remota `origin/main` == `ls-remote`, produção `/app/.git_sha` igual; worktree `/home/thanos/wt-chatwoot-etapa3`, branch `feat/etapa3-bot-optout`).
- Contrato com o WP (implementado em paralelo; usado exatamente): fork→WP via `Connecta::Runtime::PlatformClient` (`CONNECTA_FORK_TO_PLATFORM_SECRET`): `POST /attendance/v1/bot-optout {account_id, conversation_id (display_id), disabled, actor_chatwoot_user_id}` → 200 `{disabled, contact_id}`; 422 `not_human_service_inbox`; `GET /attendance/v1/bot-optout?account_id=&conversation_id=` → `{disabled}`. WP→fork (HMAC `Connecta::V1::BaseController`): `POST /connecta/v1/contacts/bot_optout {account_id, contact_id, disabled}` → espelho `custom_attributes['connecta_bot_disabled']` (true liga, chave removida no false); 200 `{contact_id, disabled}`; 404 se o contato não é da conta.
- Backend (fork): `Api::V1::Accounts::Conversations::ConnectaBotOptoutsController` (`show`/`create`, `resource :connecta_bot_optout` ao lado das rotas connecta da conversa) — autorização `show?` da conversa (qualquer agente/admin com leitura); só inboxes sob enforcement Connecta (fora disso 404); no 200 espelha o contato local; WP 422 `not_human_service_inbox` vira 422 amigável, timeout/5xx do WP vira 503. Nunca usa `contact.blocked` (derrubaria o inbound). `Connecta::V1::ContactsController#bot_optout` (HMAC, `POST /connecta/v1/contacts/bot_optout`) com 404 fora da conta e 422 em params inválidos; `route_inventory_spec` classifica `connecta/v1/contacts` na superfície plataforma→fork.
- CSAT: `Connecta::Scope::CsatPolicy.bot_disabled?` + `CsatSurveyService#eligible_for_csat?` pula a pesquisa quando `custom_attributes['connecta_bot_disabled'] == true`, em qualquer inbox.
- Frontend: item no menu de contexto da conversa (`contextMenu/Index.vue`, estado lido sob demanda ao abrir o menu; sem request por card) — "Desativar bot neste número"/"Reativar bot neste número", com diálogo de confirmação só ao desativar ("O bot deixará de responder automaticamente este número...") e alertas de sucesso/erro; `ConversationItem.vue` fecha o menu via `botOptoutChanged`; `ConnectaConversationStatus` mostra "Bot desativado neste número — atendimento humano." quando desligado; strings em `fazer-ai/locale/pt_BR|en/connecta.json` (`CONNECTA.BOT_OPTOUT`); `api/connecta.js` com `showBotOptout`/`setBotOptout`.
- Locales Rails: `config/locales/fazer_ai.{en,pt_BR,es}.yml` ganham `errors.conversations.connecta_bot_optout` (not_scoped, disabled_required, not_human_service_inbox, timeout).

## Tests

- Backend (modo runtime/tabelas de produto, sem G0; validado no CI — sem Ruby local): `spec/controllers/api/v1/accounts/conversations/connecta_bot_optouts_controller_spec.rb` (401 sem auth/outra conta/sem acesso à inbox, 404 conversa inexistente e inbox não escopada sem chamar o WP, GET com query account/display_id, POST com payload account/display_id/disabled/actor + espelho no contato, reativação remove só a chave, 422 `not_human_service_inbox` amigável sem espelho, timeout → 503); `spec/requests/connecta/bot_optout_contacts_spec.rb` (liga/desliga o espelho, 404 contato de outra conta, 422 params, 401 assinatura, 403 account divergente); `spec/services/connecta_bot_optout_csat_spec.rb` (`:not_eligible` com flag em resolução final com protocolo, envia sem flag, pula mesmo fora de inbox escopada).
- Frontend (local, vitest): `contextMenu/specs/ConnectaBotOptout.spec.js` 8/8 (rótulo por estado, confirmação ao desativar, POST, cancelamento, erro, oculto em 404/flag off); vizinhos `conversation/specs/` 178/178 em 9 arquivos; eslint 0 erros nos tocados (1 warning pré-existente `vue/no-root-v-if` em `ConnectaConversationStatus.vue`).

## Docs

- `architecture.md`: seção Etapa 3 (opt-out do bot por número).

## CI (`run_foss_spec.yml`, workflow_dispatch `full=true` no branch)

- Run 1 (`f944bf32`, run 42935082431): plan/lint-frontend/frontend-tests/backend-tests (0-3,5-7) success; backend-tests (4) failure com 3 falhas nos specs novos (causa: `friendly_status(e)` recebia a exceção em vez de `e.status` → 500 em vez de 422/503; + spy sem stub); lint-backend failure com 77 ofensas = 74 baseline + 3 novas (`FirstHashElementIndentation` ×2 no controller novo, `LineLength` no nome da superfície do inventário); security-scan failure = baseline (Brakeman em arquivos upstream + CVE em gem, nada nos tocados).
- Correção (`5f7853a6`): `friendly_status(e.status)`, payload do POST em variável local, nome da superfície encurtado, stub do spy no spec.
- Run 2 (`5f7853a6`, run 42936515087): plan success; lint-frontend success; frontend-tests success; backend-tests (0-7) TODOS success; lint-backend failure = baseline exato (74 ofensas, ZERO nos arquivos tocados); security-scan failure = baseline (Brakeman exit 3 em `search_service.rb` e outros upstream + `bundle-audit` CVE-2026-67991 em `ruby_llm`; 0 achados nos arquivos tocados).
- AC1/AC2 atendidos; sem merge na main (só branch + CI, conforme escopo).
