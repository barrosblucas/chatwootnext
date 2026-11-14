# PROJECT_STATE — chatwootnext

Estado atual verificado no código em 2026-11-14. Histórico vive em `.context/changelog/` e `.context/evidence/`; aqui só o estado vigente, otimizado para agentes LLM.

## Referência e data da verificação

- HEAD verificado: `a8b7a0eafb96e1c4c5ac65509818477bf5e8edcf` (2026-11-11, `feat(connecta): atribui protocolo ao primeiro operador que responder`), confirmado em 2026-11-14. `script/criar_admin.rb` segue untracked, nunca commitado.
- Regra: produção/CI só com fonte citada (changelog/evidência); sem fonte, "não verificado". Sem segredos, IPs ou dados pessoais aqui.

## Capacidades presentes no código

- Runtime opt-in: produção usa `Runtime::Installer` via `config/initializers/connecta_runtime.rb`; `Scope::Installer.install!` só roda em teste (`app/services/connecta/scope/installer.rb`).
- Protocolo — busca, lista e visão por etapas: `app/services/connecta/scope/protocol_search.rb`, `app/services/connecta/scope/conversation_metadata.rb`, `app/services/connecta/scope/protocol_view.rb`; frontend `app/javascript/dashboard/components/widgets/conversation/ConnectaProtocolDrawer.vue`, `ConnectaConversationStatus.vue`, `app/javascript/dashboard/components-next/NewConversation/components/ConnectaSectorPicker.vue`; decisão 007.
- Ciclo de vida do escopo: resolver fecha (`closed`), reabrir restaura, escrita em resolvida negada — `app/services/connecta/scope/conversation_resolution.rb`; decisão 005. Requisito de runtime: inbox do número humano com `lock_to_single_conversation=false`.
- Envio em recepção só pelo usuário de serviço + parked visível — decisão 004 (claim exige escopo `active`; conversa sem escopo vira `parked`).
- Transferência mediada atual: `app/services/connecta/transfer_service.rb` + `app/services/connecta/transfer/local_transaction.rb` (nota de destino genérica, sem PII da origem).
- Vínculo Fase 1 (WP provisiona/troca senha/desativa agente via HMAC): `app/controllers/connecta/v1/users_controller.rb` + `app/services/connecta/provisioning/agent_provisioner.rb`.
- CSAT Fase 2 (protocolo, push ao WP, senha gerenciada): `app/services/connecta/scope/csat_policy.rb` + `app/jobs/connecta/runtime/csat_push_job.rb` (push leva `assigned_agent_id`/`assigned_agent_name`, sem PII de contato).
- Opt-out do bot Etapa 3 (por número, menu da conversa + espelho no contato): `app/controllers/api/v1/accounts/conversations/connecta_bot_optouts_controller.rb` + `app/controllers/connecta/v1/contacts_controller.rb`.
- Primeiro operador atribui (1ª resposta humana vira `assignee`): `app/services/connecta/scope/first_agent_assignment.rb` (requer `enable_auto_assignment` desligado na inbox 9 no deploy).
- ACL robustez fork-side: lápide de grant/trinca em `app/models/connecta/revoked_grant.rb` + `app/services/connecta/scope/user_grant.rb`; graça de heartbeat em `app/services/connecta/scope/projection.rb` (TTL 120 s, graça 900 s); decisão de acesso em `app/services/connecta/scope/gate.rb`.
- Mídia protegida (frontend resolve bytes via sessão autenticada): `app/javascript/dashboard/helper/connectaProtectedMedia.js`.
- Resolve sai da lista (frontend-only, sem `scope.revoked`): `app/javascript/dashboard/helper/connectaResolveLeave.js`.

## Homologação e CI — somente com fonte

- CSAT v2: RSpec local 82/82 verde; CI via `workflow_dispatch` não disparado neste ambiente — `CHANGELOG_2026_11_11.md`.
- Etapa 3 opt-out: CI run 2 com backend-tests (0-7) success, lint = baseline 74 — `CHANGELOG_2026_11_11.md`; sem merge na main.
- Fase 1 vínculo / Fase 2 CSAT: CI verde nos runs citados; lint-backend 74 ofensas e security-scan = baselines pré-existentes — `CHANGELOG_2026_11_09.md`, `CHANGELOG_2026_11_10.md`.
- Releases de ensaio LAN 02–03/11 (imagens `teste`, TLS Caddy, Baileys): só teste local; homologação UI/E2E humano pendente onde o changelog marca pendente — `CHANGELOG_2026_11_02.md`, `CHANGELOG_2026_11_03.md`.
- Protocolo (08/11) e primeiro-operador (11/11): código pronto, CI pendente — `CHANGELOG_2026_11_08.md`, `CHANGELOG_2026_11_11.md`.
- Status atual de produção/deploy: não verificado (sem fonte citada nesta revisão).

## Pendências atuais

- CI GitHub Actions das frentes "código; CI pendente" (protocolo 08/11, primeiro-operador 11/11).
- Homologação UI/E2E humano dos ensaios LAN e da mídia protegida.
- Itens G0 de 2026-10-22 sem decisão registrada em `decisions/` (ver "Decisões abertas"): aplicabilidade atual não verificada.
- Runner G0 reexecutável: superado via prova de posse — `gotchas.md` (sem ação).

## Decisões abertas

- Nenhuma além das ADR 001–007 (todas Aceitas) — ver `decisions/README.md`.
- Herdadas do G0 (2026-10-22, sem registro em `decisions/`, reabrir só com instrução humana): pnpm do frontend; rotas Devise do super admin; `/auth/:provider` sem whitelist; teardown+preparo (recomendado: manter recusa); retry de erro genérico do AgentBot (recomendado: 1 tentativa); anexos Baileys sem ACL (recomendado: autorizar na T0.2).

## Links

- Arquitetura: `.context/architecture.md`; decisões: `.context/decisions/README.md`; armadilhas: `.context/gotchas.md`.
- Histórico por dia: `.context/changelog/`; evidências: `.context/evidence/` (`g0/`, `baileys/`).
- Cross-app (contrato WP, ADR-013, protocolo atendimento humano): monorepo `docs/integrations/` e `docs/adr/` — ver `CHANGELOG_2026_10_28.md`.

## Mapa do conteúdo removido (categoria -> onde vive agora)

- Checkpoints de build/deploy/rollback 01–03/11 (imagens, digests, healths, DB counts): `CHANGELOG_2026_11_01.md`, `CHANGELOG_2026_11_02.md`, `CHANGELOG_2026_11_03.md`.
- Consolidação F1/F2/F3/F4 + snapshots C/E (29/10, OIDs e ledger): `CHANGELOG_2026_10_29.md` + `/home/thanos/backups/consolidacao-20261029/`.
- Deploys locais 27–28/10 (bold-italic, authority, dual-role, admin nativo): `CHANGELOG_2026_10_27.md`, `CHANGELOG_2026_10_28.md` + `.context/evidence/baileys/`.
- Fase G0 22/10 (T0.x, spikes, entregas, pendências 6–12, decisões 1–5 resolvidas): `CHANGELOG_2026_10_22.md` + `.context/evidence/g0/`.
- Handoff da pausa 03/11 02:52Z: `CHANGELOG_2026_11_03.md` (retomada no plano conectacidade citado nele).
