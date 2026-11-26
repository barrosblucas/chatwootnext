# Changelog — 2026-11-26

## Intenção da feature
- Intenção: restringir atendimentos por responsável e permitir supervisão por gestor de unidade.
- Regras de negócio afetadas: atribuição, liberação, transferência, visibilidade, métricas e atualizações realtime.
- Não deve mudar: comportamento de inboxes não Connecta e acesso de administradores nativos.
- Já feito: escopo por responsável, permissão `gerir`, fila, reivindicação de respostas e correções dos cinco achados.
- Pendente: integração e implantação em produção em etapas posteriores.
- Etapa atual: validação das correções no GitHub Actions.

## Changed
- Base `d0b3ab77f678cf6ed168d6ab40b6017b90864467`: limita visibilidade e escrita por responsável, permite gestão por unidade, aplica a política de atribuição e entrega transferências entre unidades sem responsável.
- Aceita `gerir` nos catálogos de grants Connecta.
- A fila Aguardando exclui conversas atribuídas; gestores têm a aba Todos para os setores autorizados.
- A primeira resposta humana reivindica o atendimento sob lock; colegas que perdem acesso recebem `scope.revoked`, sem conteúdo.

## Tests
- Adicionada cobertura de visibilidade, atribuição, transferência, sync, lock de resposta, destinatários realtime e aba de gestor; execução no GitHub Actions.
- Dividido o teste de destinatários realtime, preservando as verificações e respeitando o limite de expectativas.

## Deploy (producao, 2026-11-26 ~21:36-21:45 UTC)
- Publicado `8b42231982498438b8be5dbd0dc6521d4ecaa9b8` (Actions run 45894705411 success) nos 3 containers Chatwoot (rails/sidekiq/premium_watch), imagem `ghcr.io/barrosblucas/chatwootnext@sha256:29397b804c1f3f0c273d03d68f9e667c16129eff26dafaf8891d0bf7bb520142` (`/app/.git_sha` == novo sha, rails healthy, 0 erros em logs 5m).
- Rollback: `conectacidade/.runtime/rollout-chatwoot-8b42231-20261126/rollback.sh` (volta a `d0b3ab77f` / `sha256:629c4287ab14`).
- Webhook id=1: subscriptions agora `["message_created", "conversation_status_changed", "conversation_updated"]` (url/secret inalterados).
