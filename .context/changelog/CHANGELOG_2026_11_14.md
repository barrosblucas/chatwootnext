# Changelog 2026-11-14

## Intenção da feature

- Intenção: limpeza e conformidade da documentação para agentes LLM (etapa 1: corrigir erros factuais provados no código; sem mudar comportamento).
- Regras de negócio afetadas: nenhuma.
- Não deve mudar: código, decisões, changelogs antigos, evidências.
- Já feito: etapa 1 — REPOMAP descreve o opt-in runtime (`Runtime::Installer` via `CONNECTA_HUMAN_NUMBER_ENABLED` + `G0Adapter`); runbook com TTL 120/graça 900 (`scope/projection.rb`); `AGENTS.md` com os remotes reais (`origin → barrosblucas/chatwootnext`, `upstream-fazer → fazer-ai/chatwoot`); aviso de remotes no skill `sync-fork`.
- Pendente: etapas 2-5 — enxugar PROJECT_STATE, CLAUDE.md -> @AGENTS.md, apagar snapshots de baseline em evidence/, triar planos concluídos e LIBERACAO_PREMIUM.md.
- Etapa atual: 1.
- Base: `a8b7a0eaf` (HEAD local == main esperada; `script/criar_admin.rb` untracked intacto).

## Fixed

- `.context/REPOMAP.md`: linha do `app/services/connecta/scope/` reescrita — `Scope::Installer.install!` só roda em teste (`scope/installer.rb:6-7`); produção usa `Runtime::Installer.install!` via `config/initializers/connecta_runtime.rb:1-3` com opt-in e tabelas verificadas.
- `app/services/connecta/scope/installer.rb:1`: comentário corrigido (só linha de comentário) — `install!` é teste; produção chama os `install_*` individuais via runtime.
- `docs/runbooks/connecta-numero-contingencia.md`: `CONNECTA_ACL_HEARTBEAT_TTL_SEC` padrão 60 → 120 (`scope/projection.rb:5,13-15`); adicionada `CONNECTA_ACL_STALE_GRACE_SEC` padrão 900 (`scope/projection.rb:9,17-19`).
- `AGENTS.md` (seção Git Remotes & PRs): remotes reais — trabalho/PRs no `origin` (`barrosblucas/chatwootnext`); `upstream-fazer` (`fazer-ai/chatwoot`) só para sync. `CLAUDE.md` e `.windsurf/rules/chatwoot.md` são symlinks para `AGENTS.md`, logo idênticos.
- `.claude/skills/sync-fork/SKILL.md`: aviso no topo de que os remotes/fluxos descritos (`fazer-ai/*`, `chatwoot-pro`) não existem neste clone; sem reescrita do fluxo.

## Etapa 2b · PROJECT_STATE enxugado (docs; sem código)

- Reescrita: `.context/PROJECT_STATE.md` 284 → 58 linhas. Seções: referência/data (HEAD `a8b7a0eafb96e1c4c5ac65509818477bf5e8edcf` + regra sem-fonte=não-verificado), capacidades (cada linha com path verificado no código), homologação/CI só com fonte, pendências atuais, decisões abertas, links, mapa do removido.
- Correção de path herdada: controller de opt-out vive em `app/controllers/api/v1/accounts/conversations/connecta_bot_optouts_controller.rb` (não na raiz de controllers); frontend Connecta em `components/widgets/conversation/` e `components-next/NewConversation/components/`; models Connecta sob `app/models/connecta/` (`revoked_grant.rb`, `user_grant.rb`).
- Verificação pré-remoção: cada categoria histórica tem casa (`rg` por frase distintiva) — builds/ensaios 01–03/11 em `CHANGELOG_2026_11_01/02/03.md`, consolidação F1–F4 em `CHANGELOG_2026_10_29.md` + backups externos, deploys 27–28/10 em `CHANGELOG_2026_10_27/28.md` + `evidence/baileys/`, G0 22/10 em `CHANGELOG_2026_10_22.md` + `evidence/g0/`, handoff pausa 03/11 em `CHANGELOG_2026_11_03.md`. Nenhum conteúdo órfão: sem seção "Histórico movido".
- Referências preservadas: 85 menções a `PROJECT_STATE.md` em `.context/`+`docs/` (quase todas em snapshots de `evidence/g0/` e baselines históricos); 1 citação com linha (`CHANGELOG_2026_10_22.md:123` → `PROJECT_STATE.md:22`) mantida intacta como história.
- Validação: `wc -l` 58; `git diff --check` limpo.

## Etapa 4+5 · Snapshots, planos e LIBERACAO_PREMIUM (docs; sem código)

- Removidos (`git rm -r`, 31 arquivos, 2905 linhas): `.context/evidence/g0/03-baseline-arquivos/` (8 arquivos), `.context/evidence/g0/03-retomada-baseline-arquivos/` (17 arquivos), `.context/evidence/g0/05-baseline-arquivos/` (6 arquivos). Cópias byte a byte de `.context/` de outubro; hashes sobrevivem em `00/03/03-retomada/05-*-sha256.txt`. Recuperáveis com `git show a8b7a0eaf:<path>`. Changelogs antigos (ex. `CHANGELOG_2026_10_22.md:168,195`) citam os snapshots e foram mantidos intactos como história. Nenhum doc ativo referenciava os diretórios; `.context/REPOMAP.md:36` atualizado para a nova composição do `evidence/g0/`.
- Mantidas todas as demais evidências, incluindo `g0/32-transfer-lint.md` (citado em briefing; verificado presente) e `08-baseline-arquivos/` (fora do escopo da remoção).
- Planos arquivados (`git mv`, política de `.context/plans/README.md:5` — concluído move para `archive/`, não apaga): `.context/plans/2026-10-24-g0-rf4-rf5-pending-deliveries.md` → `.context/archive/plans/` (341 linhas; spike de teste encerrado, hooks de entrega em `app/services/connecta/scope/installer.rb:97-110`) e `.context/plans/2026-10-25-plano-commit-connecta.md` → `.context/archive/plans/` (142 linhas; superado pelo consolidado `1772a68a3`). Linha de status no topo de cada um. Links restantes aos paths antigos vivem só em evidências históricas (`g0/40,41,43,49,51,44-*.md`) e no changelog antigo (`CHANGELOG_2026_10_25.md:136,144`) — mantidos como história, sem edição.
- `LIBERACAO_PREMIUM.md` (612 linhas) removido (`git rm`): guia genérico de self-hosted upstream com paths obsoletos (`/home/thanos/chatwoot_atende`, não este fork), 7 features e setup de dev-machine (screen/puma/vite, inotify) — conteúdo aplicável deste fork vive em `LIBERACAO_PREMIUM_FAZER.md` (86 linhas, fork `fazer-ai/chatwoot` CE, 15 features via `script/liberar_premium.rb` existente no repo) e o premium já foi consolidado em `1772a68a3`. `DEPLOY_FAZER.md` referencia só `script/liberar_premium.rb`, sem link ao removido. Recuperável com `git show a8b7a0eaf:LIBERACAO_PREMIUM.md`. `DEPLOY_FAZER.md` e `CUSTOM_BRANDING.md` intocados.
- Etapa atual: 5 concluída (chatwootnext).
