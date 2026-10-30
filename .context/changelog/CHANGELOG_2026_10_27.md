# Changelog 2026-10-27

## Added (I.1a — admin nativo same-account: helper + Gate + Query)
- `app/services/connecta/scope/native_admin.rb` (novo): predicado central `administrator?(user, account)` que reconsulta `AccountUser(role: administrator)` a cada chamada — sem grant setorial, sem cache, sem papel global. `authorized_for?(user, conversation)` valida a conta DO RECURSO (cross-account sempre nega). Reaproveitável por HTTP (I.1b) e realtime (I.2).
- `spec/connecta/scope_policy_query_spec.rb`: bloco novo "administrador nativo da conta (I.1a)" com 8 exemplos — lista full + auditoria de metadado, leitura auditada por conversa, escrita pelo endpoint real, regressão nominal só-leitura, dual admin A/B, Gate cross-account, rebaixamento e remoção sem privilégio residual.

## Changed (I.1a)
- `app/services/connecta/scope/gate.rb`: `decide` libera read/write quando `NativeAdmin.authorized_for?` prova admin na conta da conversa; nominal (só read auditado) e regras de agente inalteradas.
- `app/services/connecta/scope/conversation_query.rb`: nativo da conta da consulta lista todas as conversas marcadas DA CONTA (`Current.account.inboxes ∩ marcadas`) com auditoria de metadado; nunca de outra conta.

## Tests
- `spec/connecta/scope_policy_query_spec.rb`: 46 exemplos, 0 falhas (I.1a 39 + I.1b 7: transcrição nativa, policy destinos, transação A→B real, negativas mesma-unidade/inválida/agent/cross-account, rebaixamento, can_transfer).
- `spec/connecta/attachment_download_scope_spec.rb`: 29 exemplos, 0 falhas (inclui 3 novos I.1b: download nativo 200 auditado, cross-user negado+cota, upload direto cria blob).
- `spec/connecta/scope_related_http_spec.rb`: 64 exemplos, 0 falhas (regressão HTTP relacionada).
- `spec/connecta/containment_spec.rb`: 14 exemplos, 0 falhas (regressão contenção).
- `spec/connecta/transfer_integration_spec.rb`: 11 exemplos, 0 falhas (regressão transação local).
- RuboCop check-only nos 5 Ruby tocados: sem ofensas. `git diff --check`: limpo.

## Added (I.1b — admin nativo nos caminhos HTTP reais + transferência)
- `app/services/connecta/scope/conversation_http_hook.rb`: `connecta_scope_transcript_guard!` libera também nativo same-account (auditoria allow/deny preservada).
- `app/services/connecta/runtime/transfer_policy.rb`: `ensure_transfer_permission!` retorna antes do grant quando `NativeAdmin.authorized_for?` prova admin na conta da conversa; destino continua validado na transação (mesma unidade/inválida negam).
- `app/controllers/api/v1/accounts/conversations/connecta_scopes_controller.rb`: `can_transfer` true para nativo same-account via helper privado (métricas do RuboCop preservadas).

## Pendências (fora deste passo)
- I.2: realtime/socket/DeliveryCheck/admin metadata (não tocados).
- Full e deploy NÃO declarados neste passo.

## Added (I.1b-runtime — prova de transferência em tabelas produto, fecha lacuna do I.1b)
- `spec/connecta/native_admin_runtime_transfer_spec.rb` (novo, 6 exemplos): endpoint real `POST connecta_transfer` + `Connecta::Runtime::TransferTransaction` de produto com fixtures sintéticas nas tabelas PRODUTO do G0 existente (`G0Adapter::TABLES` via `around`, sem schema:load/migração). Doubles só de fronteira (`PlatformClient#post` devolve `case_version 2`/`to_session_ref`; jobs só agendamento). Positivo: nativo sem grant A→B responde 202 `pending_activation`; `TransferRecord` produto com `transfer_id`/`prepared_at`/`platform_session_ref`/`summary_length`; scope destino `pending_activation` com `transfer_id`/`platform_session_ref`; origem `transferred_out`; `Outbox transfer.committed` + `TransferCommitJob`. Negativos sem efeitos: destino outra conta (cross-account), destino inválido, mesma unidade, rebaixamento admin→agent na mesma sessão, agent sem grant `transferir`.
- Nenhuma correção de implementação necessária: a prova passou verde na primeira execução contra o código autorizado pronto ( endpoint + `TransferPolicy` + `TransferTransaction`).

## Tests
- `spec/connecta/native_admin_runtime_transfer_spec.rb` (novo): 6 exemplos, 0 falhas (endpoint/SUT reais; fixtures produto sintéticas reversíveis via rollback transacional).
- `spec/connecta/scope_policy_query_spec.rb` (regressão focal): 46 exemplos, 0 falhas.
- `git diff --check`: limpo. RuboCop check-only na spec nova: sem ofensas (após agrupar asserções do positivo em `aggregate_failures` e reusar `G0Adapter::TABLES` no `around`, sem constante própria).

## Added (I.2 — realtime nativo same-account full, fecha pendências finitas)
- `app/services/connecta/scope/socket_hook.rb`: `user_tokens` soma `native_tokens_for_account` (lookup direto por `AccountUser administrator`, sem exigir inbox membership) ao filtro `socket_reader?` (Gate+auditoria). Menção direta libera nativo same-account; nominal segue fora (sem conteúdo). `enqueue_admin_metadata`/`socket_admin_tokens` restritos a role nominal; nativo recebe conteúdo pelo job normal. Contato criado/atualizado/excluído segue excluindo nativo do canal de contato (nativo administra por conversa/mensagem/evento).
- `app/services/connecta/scope/delivery_context.rb`: `conversation_context` passa a emitir kind `conversation_and_native_admin` separando `native_admins` ([id, epoch]) de `users`; `native_same_account_ids` exige `administrator?` + `authorized_for?` na conta DO RECURSO (cross-account nunca entra).
- `app/services/connecta/scope/delivery_check.rb`: kind `conversation_and_native_admin` (e legado `native_admin`) revalida no momento da entrega vínculo atual + epoch + conta do recurso e audita via `Gate#read?` (`socket_job_native_admin`); nega sem revalidação (fail closed).
- `app/services/connecta/scope/admin_metadata_delivery_guard.rb`: `role_still_allowed?` agora só role nominal com grant+`Projection#admin?`; nativo não entra neste canal.

## Tests (I.2 fechamento — 3 regressões restantes, G0 existente via --spec --apply)
- `spec/connecta/containment_spec.rb`: 14 exemplos, 0 falhas.
- `spec/connecta/transfer_integration_spec.rb`: 11 exemplos, 0 falhas.
- `spec/connecta/native_admin_runtime_transfer_spec.rb`: 6 exemplos, 0 falhas.
- Nenhum bug de implementação revelado pelos 3 lotes: nenhuma correção de código nesta atribuição.
- RuboCop check-only nos 19 Ruby da tarefa (10 app + 9 spec): sem ofensas. `git diff --check`: limpo.
- Enterprise conferido: `enterprise/app/listeners/enterprise/action_cable_listener.rb` só trata `copilot_message_created` (broadcast direto ao dono do thread); nenhum overlay toca `ActionCableBroadcastJob`, `Notification::*Job`, transcript, anexos ou transfer. Hooks Connecta instalados só em `Rails.env.test?` via `Installer.install!`; fora dos specs G0 o código nativo permanece.

## Limites / não declarado
- Contato: nativo fica de fora do canal de contato por desenho (ContactVisibility); administra por conversa/mensagem/evento. Nenhuma evidência de lacuna real de fluxo encontrada nos lotes; não ampliado sem evidência.
- Sem deploy, build de imagem, containers novos, provisionamento, teardown, schema load, DB runtime, dados reais, WP/monorepo, B5, .env/segredos, commits ou dependências. Monorepo baseline e os 3 arquivos deploy preexistentes não foram tocados por esta atribuição.

## Deploy local (D.1 — 2026-10-27, camada mínima backend)

- Build antigo pré-reinício (`sh_17b3f351c…`: output vazio, sem processo build ativo) declarado indisponível; sem duplicar build ativo.
- Base `connecta-e2e-fork:rollback-2026-10-26-c82f2d5` (`c82f2d5…`, sem pull) compatível com tree aprovado: initializer/feature/g0_adapter/installer/transfer_transaction idênticos host×base; só os 9 app aprovados divergiam + `native_admin.rb` ausente.
- `docker build --pull=false -t connecta-e2e-fork:local -t connecta-e2e-fork:20261027-local-coded-layer /tmp/opencode/fork-layer` (COPY dos 10 .rb aprovados): `BUILD-EXIT:0`; nova imagem `sha256:a9d4a8c733e9c14e65fccdabc060f234d229ab5823eddfd450410d761564b7b5`.
- Recriados SOMENTE `fork-web`/`fork-worker` (`up -d --no-deps --force-recreate`): web `a9cbeb800938` healthy, worker `ea4b0fe40f00` running `RestartCount=0`, ambos nova imagem. SHA dos 10 dentro dos 2 = tree. Runner: NativeAdmin+Gate carregáveis, FeatureFlag=true (sem dados reais). Healthcheck `/api` OK. wp/B5/Baileys/bancos/redis/3 deploy/monorepo intactos. Rollback tag preservada. E2E funcional manual pendente. Evidência: `.context/evidence/baileys/2026-10-27-admin-native-local-deploy.md`.
- Correção factual: hooks Connecta instalados fora de test via opt-in (`config/initializers/connecta_runtime.rb`), não "só em `Rails.env.test?`".
- Correção documental (2026-10-27, sem runtime): evidência D.1 corrigida — snapshots `git status --short` literais dos dois repos (changelog+evidência como `??`, sem commit), plano monorepo `2026-10-26-baileys-fechamento-ciclo-local.md`, rollback com comandos completos restritos a fork-web/fork-worker marcados NÃO EXECUTADOS.
