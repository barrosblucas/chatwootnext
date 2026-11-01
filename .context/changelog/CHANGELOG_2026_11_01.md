# Changelog — 2026-11-01

## Merge fix/baileys-missing-url-422 em main (fast-forward, sem build/deploy)

- `main` avançada por fast-forward de `1772a68a3` para `03c55d2b9` (`fix(baileys): validate provider URL and update API deployment`), sem perda: 13 arquivos, 221 inserções, 9 remoções. Conteúdo do fix inalterado (código, specs, locales en/pt_BR/es, manifestos `deploy/baileys-api/`, override de teste, `.context`).
- Checkout canônico: `/home/thanos/chatwootnext`, branch `main`. Worktree temporária `/tmp/opencode/chatwootnext-baileys-422` removida via `git worktree remove` (sem `--force`, limpa e sem bind mounts para o caminho). Branch `fix/baileys-missing-url-422` preservada como referência histórica.
- Override de teste agora canônico em `/home/thanos/chatwootnext/docker-compose.teste-lan.baileys-override.yml`. Próximas operações Compose de teste devem usar os caminhos home:
  `docker compose -f /home/thanos/chatwootnext/docker-compose.teste-lan.yml -f docker-compose.teste-lan.baileys-override.yml up -d rails sidekiq`
  (com `BAILEYS_PROVIDER_DEFAULT_API_KEY` exportada em memória; nunca literal).
- Validação: `git status --short` antes do commit mostrava só os dois docs desta etapa; `git merge-base --is-ancestor fix/baileys-missing-url-422 main` yes; `git diff --check` limpo; caminho temporário ausente; override presente no home; nenhum bind mount para o caminho temporário (0 ocorrências nas inspeções de mount).
- Não executado: `ruby -c` (sem Ruby neste ambiente), `bundle exec rspec`/`rubocop` (sem toolchain Ruby; sem instalar/migrar/provisionar), nenhum build/restart/recriação de container. Código do fix ainda NÃO foi buildado nem ativado no runtime (imagem `chatwootnext:teste` anterior ao fix, conforme changelog de 2026-10-31).
- Riscos/ressalvas: labels Compose históricos dos containers de teste ainda apontam para o override no caminho temporário (somente metadados; nada recriado nesta etapa); documentação desta etapa foi commitada em commit documental posterior a `03c55d2b9` e publicada em `origin/main` (autorização do usuário em 2026-11-01); diretório `/tmp/opencode/chatwootnext-baileys-runtime` (API Baileys) não tocado.
