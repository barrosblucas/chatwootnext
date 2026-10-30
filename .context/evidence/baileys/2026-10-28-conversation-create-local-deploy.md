# Deploy local — liberação de criação de conversa em inbox Baileys (2026-10-28)

Publicação seletiva do patch que remove o bloqueio customizado universal de
criação (`connecta_scope_create_guard!` + callback `prepend_before_action`),
passando a valer a autorização nativa de inbox
(`authorize @inbox, :show?` / `authorize @contact_inbox.inbox, :show?`).

## Escopo e autorização
- Pedido explícito do usuário: "Faça a publicação" (ChatwootNext 192.168.1.32:3006).
- Autorizado: tag rollback, build curado só do patch, promoção, recriação
  seletiva web+worker com configuração/volumes/portas atuais, rollback se falha.
- Sem DB/migração/Redis/dados reais/`.env`/Env/segredos/outros serviços/ports/
  config/volumes, sem dirty full build, sem commit/push.
- Nenhum outro agente ativo nesta janela.

## Preflight (read-only)
- `git status --short`: idêntico ao baseline do briefing (30 modificados +
  untracked conhecidos); nenhum arquivo novo criado pela tentativa anterior.
- Runtime antes: web+worker em imagem ID
  `sha256:08a33ebf7aefffc3c2ddd33e75e70638cf11bc554a6396b87a595f0d9f0821f3`
  (`:local`), web healthy, worker running, RestartCount 0 ambos.
- Bind runtime: `3000/tcp -> 192.168.1.32:3006` (LAN). Compose WORKTREE
  (`deploy/e2e/compose.yml`) declara o mesmo bind LAN; HEAD declararia loopback
  e por isso NÃO foi usado (requisito do briefing).
- Campos operacionais conferidos no Compose WORKTREE (sem segredos):
  fork-web `bundle exec rails s -b 0.0.0.0 -p 3000`, healthcheck
  `wget http://127.0.0.1:3000/api` (15s/20 tentativas), restart unless-stopped;
  fork-worker `bundle exec sidekiq -C config/sidekiq.yml`;
  ambos imagem `connecta-e2e-fork:local`, volume `fork_storage:/app/storage`,
  rede `connecta-e2e-net`, sem `env_file` (`.env` lido pelo Compose, conteúdo
  nunca aberto).
- `docker port connecta-e2e-fork-web` pós-deploy: `3000/tcp -> 192.168.1.32:3006`
  (inalterado). Mounts: `connecta-e2e_fork_storage:/app/storage` (inalterado).
- Divergência de hash de config (worktree 5987ec…/033542… vs labels ativos
  e2a8f5…/6227fd…): causa não determinada, compatível com normalização/versão;
  nenhuma mudança concreta nos campos dos dois alvos foi encontrada, então
  nada extra foi "corrigido" (conforme briefing: não forçar hash idêntico).

## Delta publicado (exclusivo)
- Extração dos arquivos vivos da imagem ativa via `docker cp` confirmou o
  guard presente no live (`911bf1e7…` / `ac28a1f2…`).
- Verificação byte a byte: worktree = live menos SOMENTE o bloco do guard
  (816 bytes) + a linha do callback. Nenhum outro hunk foi copiado — em
  particular, o hunk preexistente de transcrição do worktree JÁ estava no live
  (imagem bold-italic), então nada dele foi publicado como novidade.
- Staging curado: `/tmp/opencode/fork-create-liberation-20261028/` com
  `Dockerfile` (`FROM connecta-e2e-fork:local` + COPY dos 2 arquivos).
- Hashes do candidato (iguais worktree, iguais live nos containers pós-deploy):
  - `conversation_http_hook.rb`: `46d99c7848ea460f003104034c953f0b875f5c079956f684f68277643abec480`
  - `installer.rb`: `8eb80c8d14598138e694541aa6034409bb7ec3bf698dab53a6117432afe1301d`
- `ruby -c` (toolchain 3.4.4): Syntax OK nos dois arquivos.
- `grep connecta_scope_create_guard` no candidato e nos containers: 0
  ocorrências (ausência confirmada).

## Imagens e tags
- ROLLBACK (preservada antes de promover, ID ativo real):
  `connecta-e2e-fork:rollback-2026-10-28-08a33eb` =
  `08a33ebf7aef` (full `sha256:08a33ebf…f3`).
- CANDIDATA (build curado, 2 COPY sobre base ativa, `--pull=false`):
  `connecta-e2e-fork:candidate-20261028-create` =
  `272134b00b24` (full `sha256:272134b00b24d4f6c94081d07ee71614bd760ef9ac6e36a1dad46a2f6014811c`).
- PROMOVIDA: `connecta-e2e-fork:20261028-conversation-create` (mesmo ID) e
  retag `connecta-e2e-fork:local` para o mesmo ID.
- Rollbacks anteriores intactos (`rollback-2026-10-28-2d1fe4b`,
  `rollback-2026-10-28-a9d4a8c`, `rollback-2026-10-28-8b3e758`,
  `rollback-2026-10-26-c82f2d5`).

## Recriação seletiva
- Comando: `docker compose -p connecta-e2e -f deploy/e2e/compose.yml up -d
  --no-deps --force-recreate fork-web fork-worker` (arquivo da WORKTREE).
- Resultado: `Container connecta-e2e-fork-web Recreated`,
  `Container connecta-e2e-fork-worker Recreated`, ambos `Started`.
- Nenhum outro serviço recriado: StartedAt dos demais inalterados
  (wp, baileys-api/redis, postgres/redis do fork, wp-admin etc.).
- Sem `down`, sem remoção de volumes, sem prune, sem remoção de imagens.

## Saúde pós-deploy
- `docker ps`: `connecta-e2e-fork-web connecta-e2e-fork:local Up … (healthy)`;
  `connecta-e2e-fork-worker connecta-e2e-fork:local Up …`.
- Web: imagem `sha256:272134b0…`, `restarts=0`,
  `started=2026-10-28T22:51:08Z`, `status=running`, `health=healthy`.
- Worker: imagem `sha256:272134b0…`, `restarts=0`, `status=running`,
  `started=2026-10-28T22:51:08Z`, `oom=false`.
- HTTP LAN: `curl http://192.168.1.32:3006/api` → `200` (só status verificado,
  sem dump de conteúdo).
- Arquivos publicados conferidos DENTRO do web em execução: hashes iguais ao
  candidato; guard ausente.
- Sem rollback necessário (saúde OK na primeira verificação).

## Testes
- Sem rerun de DB nesta etapa: delta idêntico ao já validado em G0 na etapa de
  código (38 `scope_http_filter` + 46 `scope_policy_query`, 0 falhas, RuboCop
  limpo), conforme autorização do briefing ("sem testes DB novos se delta
  idêntico").
- Prova funcional de criação real (conversa de verdade no 3006) NÃO executada:
  criaria dados reais; fica como E2E humano pendente.

## Limites e riscos residuais
- Imagem publicada contém SOMENTE este patch sobre a base bold-italic; demais
  hunks dirty do checkout NÃO foram publicados (permanecem só no worktree).
- `GET /api` 200 prova boot+roteamento, não prova criação fim a fim com usuário
  real (pendente E2E humano, sem dados reais tocados aqui).
- Compose WORKTREE continua dirty vs HEAD (bind LAN + outros serviços WP/Baileys
  já em uso); nenhum arquivo de Compose foi editado neste deploy.
