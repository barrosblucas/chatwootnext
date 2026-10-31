# Changelog — 2026-10-31

## Fixed

- Inbox WhatsApp Baileys sem URL configurada agora falha como erro de validação controlado (422 via `provider_config`) em vez de 500 por `Errno::ECONNREFUSED` com host vazio (`app/services/whatsapp/providers/whatsapp_baileys_service.rb`: guarda `valid_provider_url?` em `validate_provider_config?`; nenhuma URL/chave é registrada no log).
- Refinamento: URL Baileys ausente/inválida agora devolve mensagem acionável própria (`errors.inboxes.channel.baileys_url_not_configured` nos overlays fork en/pt_BR/es: "URL da API Baileys não configurada ou inválida" e equivalentes) em vez de `Invalid Credentials`, que levava a revisar a chave errada. Serviço levanta o `Whatsapp::Session::Errors::InvalidConfig` existente (fora do `with_error_handling`, sem marcar conexão); `Channel::Whatsapp#validate_provider_config` o converte em erro de validação (resgate estreito, só `InvalidConfig`). Resposta negativa real da API mantém `Invalid Credentials`; outros providers intocados.

## Tests

- Regressão serviço (`spec/services/whatsapp/providers/whatsapp_baileys_service_spec.rb`): URL ausente/vazia, sem host, malformada e com esquema não-HTTP(S) levantam `InvalidConfig` sem chamada HTTP (`HTTParty.get` não invocado); sem override de inbox com `DEFAULT_URL` válido valida via HTTP stubado; sem override e sem default levanta; caminho válido e recusa da API inalterados.
- Regressão model (`spec/models/channel/whatsapp_spec.rb`): URL ausente → `save` falso com a mensagem de URL (sem `Invalid Credentials`, sem HTTP); 401 da API → mantém `Invalid Credentials`.
- Validação executada: `ruby -c` nos quatro arquivos Ruby alterados (Syntax OK, toolchain Ruby 4.0.7); `ruby scripts/i18n/fork_translations.rb check` (1050 chaves en, es/pt_BR 100%); harness isolado da regra de URL em stdlib `URI` (10/10 casos); `git diff --check` limpo.
- Não executado: `bundle exec rspec` e `bundle exec rubocop` — Gemfile exige Ruby 3.4.4, indisponível neste ambiente (somente 4.0.7 no toolchain); sem `bundle install` correspondente. Sem banco/serviços provisionados; nenhum dado real acessado. Sem teste 422 end-to-end.

## Docs

- Nota de armadilha registrada em `.context/gotchas.md` (URL Baileys hostless → `ECONNREFUSED` fora da validação; refinamento da mensagem).

## Added

- Override de teste `docker-compose.teste-lan.baileys-override.yml` (worktree, sem segredos): Rails/Sidekiq recebem `BAILEYS_PROVIDER_DEFAULT_URL=http://baileys-api:3000` + chave via interpolação `${BAILEYS_PROVIDER_DEFAULT_API_KEY:?}` (exportada em memória do `.env` privado 0600), entram na rede externa `chatwootnext-baileys-teste_baileys-edge` mantendo a rede `default`; entrypoint do Rails sobrescrito para pular `rake db:chatwoot_prepare` preservando pid/cache, espera do Postgres e `bundle check`. Runtime privado (fora do Git): `/tmp/opencode/chatwootnext-baileys-runtime/` (`docker-compose.baileys-teste.yml` derivado canônico + `.env` 0600).
- Stack Baileys de teste `chatwootnext-baileys-teste` (imagens canônicas fixadas, sem exposição extra além do bind localhost `127.0.0.1:3025`): `baileys-api` + `redis` dedicado com volume próprio `chatwootnext-baileys-teste_redis-data`. Chave de teste registrada no Redis da API via `bun scripts/manage-api-keys.ts create user` (a imagem v1.21.0 valida `x-api-key` contra Redis `@baileys-api:api-keys:*`, não contra variável de ambiente — ver gotchas).

## Changed

- Rails/Sidekiq de teste recriados com a mesma imagem `chatwootnext:teste` (sha `236e2c966cb3`), mesmos volumes Postgres/Redis/storage e sem `db:chatwoot_prepare`/migrações (log confirma `Skipping db:chatwoot_prepare`); `GET /` do Chatwoot no host de teste local (porta 3000) volta 200; `GET /status/auth` a partir do Rails com a chave em memória volta 200 `OK` (URL com host `baileys-api`, sem host vazio). Correção defensiva do worktree segue NÃO implantada (imagem atual é anterior ao fix); RSpec segue não executado neste passo.

## Fixed (operação QR, ~22:50 UTC)

- API Baileys de teste atualizada `v1.21.0` → `v3.3.0` fixada por digest (`ghcr.io/fazer-ai/baileys-api:v3.3.0@sha256:a6f55bba...`, índice multi-arch) + `stop_grace_period: 45s` no compose privado do runtime (exigência das notas do release: lease 30s; Redis AOF já estava ligado). Só o serviço `baileys-api` foi recriado; Redis dedicado, volumes, chave de teste e Rails/Sidekiq intactos, sem migrações.
- API Baileys de teste atualizada `v3.3.0` → `v3.7.3` (última estável oficial, SDK `7.0.0-rc14`), fixada por digest (`ghcr.io/fazer-ai/baileys-api:v3.7.3@sha256:3b85a133...`, pedido explícito do usuário). Recriado SOMENTE `baileys-api` (`up -d --no-deps`); Redis dedicado (Up ~1h, AOF/volume/chave intactos), Rails/Sidekiq/Postgres/Redis originais não recriados (Up 58min/12h). Digest efetivo do container confere com o fixado; `GET /status` 200, Chatwoot `/` 200, job `BaileysConnectionCheckSchedulerJob` pós-upgrade executado limpo sem erros de auth. `GET /status/auth` direto: validação BLOCKED por policy gate (scanner recusou `docker exec ... node -e fetch...`; sem bypass, sem alternativa em arquivo). Renovação `POST /connections` NÃO executada: estado pareado/não-pareado não confirmável por meio permitido (leitura de credenciais/keys exigiria segredo), e a regra manda não tocar sessão possivelmente pareada; usuário pode gerar novo QR pelo retry no modal da inbox (re-POST automático). Sem migrações, sem pareamento, sem envio.
- Causa do QR ausente: loop de auto-resume/reconnect da versão pré-lease (SDK 6.7.18 com `clientVersion=default`) — `connection.ts` engolia o `connecting` sem QR como "reconnecting" e o socket nunca chegava ao evento com QR; rede provada saudável (DNS + TLSv1.3 + HTTPS 200 em `web.whatsapp.com` de dentro do container). v3.3.0 (SDK `7.0.0-rc13`) não auto-resume pareamento pendente no boot e busca a versão WA atual; `Reconnect count exceeded` zerado após o upgrade.
- Conexão de teste (única, comprovadamente não pareada via metadados: `hasCreds=false paired=false`) renovada com novo `POST /connections` usando o mesmo `webhookUrl`/`webhookVerifyToken`/`clientName` lidos do Redis em memória (nada impresso). Evidência booleana fim a fim sem expor QR/telefone: webhook `connection.update` com `qr` presente (2 QRs distintos, 22:49 e 22:50) → Chatwoot converte para `qr_data_url` e faz broadcast `inbox.provider_connection_updated` (`connection: connecting`, `error: nil`) — antes era `qr=nil` em loop. `GET /` Chatwoot segue 200.
