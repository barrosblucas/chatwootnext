# deploy/baileys-api — manifesto do transporte (T7.1)

Estado: **NÃO EXECUTADO** — arquivos de configuração/documentação. Apenas
`docker compose ... config` (render, sem subir) foi rodado na frente FORK-c9,
com valores fake de `.env.example` copiados para `/tmp/opencode`; nenhuma imagem
foi baixada, nada foi implantado.
QR, pareamento, conexão do número e produção seguem proibidos sem
autorização humana específica.

Registro desta frente: este README é o registro operacional (o briefing
proíbe escrever em `.context/` para evitar colisão com a outra frente).

## Como o fork alcança o serviço (nomes REAIS, verificados no código)

Arquivo-fonte: `app/services/whatsapp/providers/whatsapp_baileys_service.rb`
(linhas 9–11, 22–30, 345–352) e `docker-compose.coolify.yaml` (linhas 27–30).

| Variável (no .env DO FORK)              | Uso real no código                                     |
|-----------------------------------------|--------------------------------------------------------|
| `BAILEYS_PROVIDER_DEFAULT_URL`          | Base de `GET /status`, `GET /status/auth`, `POST/DELETE /connections/:phone`, `/media/:id` |
| `BAILEYS_PROVIDER_DEFAULT_API_KEY`      | Cabeçalho `x-api-key` de TODAS as chamadas ao provider |
| `BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME`  | `clientName` enviado no setup/import da conexão        |
| `BAILEYS_WHATSAPP_GROUPS_ENABLED`       | `groupsEnabled` no setup (`false` por padrão)          |

Apontamento para este compose (rede interna, sem porta pública):

```sh
BAILEYS_PROVIDER_DEFAULT_URL=http://baileys-api:3000
BAILEYS_PROVIDER_DEFAULT_API_KEY=<mesmo valor de BAILEYS_API_KEY deste compose>
BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME=<mesmo valor de BAILEYS_CLIENT_NAME deste compose>
```

> **PENDÊNCIA REGISTRADA (T7.1):** não existe nenhuma variável de configuração
> real no fork com nome `CONNECTA_BAILEYS_URL` (ou equivalente `CONNECTA_*`
> para endpoint do baileys-api). Grep em `app/` confirma: as únicas chaves de
> transporte são as `BAILEYS_PROVIDER_*` acima; as `CONNECTA_*` do fork são
> `CONNECTA_HUMAN_NUMBER_ENABLED`, `CONNECTA_ACCOUNT_ID`,
> `CONNECTA_PLATFORM_URL`, `CONNECTA_FORK_TO_PLATFORM_SECRET`,
> `CONNECTA_PLATFORM_TO_FORK_SECRET`, `CONNECTA_DISPATCH_WAIT_MS`,
> `CONNECTA_ACL_HEARTBEAT_TTL_SEC`, `CONNECTA_RECEPTION_ORG_UNIT_ID`,
> `CONNECTA_TRANSFER_ENABLED`, `CONNECTA_GATEWAY_URL`, `CONNECTA_TRANSFER_SECRET`
> — nenhuma aponta para o baileys-api. **Não foi criado código novo de runtime
> para isso** (fora do escopo autorizado); o apontamento oficial segue sendo
> `BAILEYS_PROVIDER_DEFAULT_URL`.

## O que este compose entrega

- `baileys-api`: imagem com tag e digest fixados (procedência na seção abaixo),
  `restart: unless-stopped`, `NODE_ENV=production`, `command: ['bun', 'src/index.ts']`
  (a imagem usa Bun; sem argumentos ela só imprime a ajuda e sai), senha do Redis
  sempre via variável, healthcheck em `GET /status` (responde 200 sem `x-api-key`).
  Redes: `baileys-internal` (Redis, `internal: true`) e `baileys-edge` (bridge, só
  para o bind de loopback do host). Publicação: `127.0.0.1:3025:3000` (ver abaixo).

### Publicação em loopback (exceção documentada)

O `baileys-api` publica `127.0.0.1:3025:3000`. Motivo: o fork roda como processo
no host e precisa alcançar a API em `http://127.0.0.1:3025`. A rede
`baileys-internal` é `internal: true` e o Docker não publica portas nela, por isso
o serviço também entra na bridge `baileys-edge`, que é a única a receber o bind.

**Não é exposição pública:** o bind é sempre em `127.0.0.1` (nunca `0.0.0.0`), então
só processos do próprio host alcançam a porta. O Redis continua sem nenhuma porta
publicada e fora da bridge. Qualquer alteração para `0.0.0.0` ou para outra
interface exige autorização humana.
- `redis`: `redis:7-alpine`, `restart: unless-stopped`, `appendonly yes`
  (persistência AOF em volume nomeado `baileys-redis-data`), senha obrigatória
  via `BAILEYS_REDIS_PASSWORD` (nunca literal), sem porta pública, healthcheck
  `redis-cli ping` autenticado via `REDISCLI_AUTH`.

## O que NUNCA pode ser exposto

1. `BAILEYS_API_KEY` / `BAILEYS_PROVIDER_DEFAULT_API_KEY` — autentica TODAS as
   chamadas; vazamento permite parear, ler QR, desconectar e importar sessão.
2. `BAILEYS_REDIS_PASSWORD` — dá acesso à sessão/fila do transporte.
3. QR (`qrDataUrl`), payload de `import-session`, `webhook_verify_token`.
4. Conteúdo de conversas, anexos e mídia que trafegarem pelo serviço.
5. O próprio serviço: a única publicação é `127.0.0.1:3025` (loopback, ver a
   seção acima). Nunca publicar em `0.0.0.0`, em IP de rede ou em porta do Redis.
   `GET /status` responde 200 sem `x-api-key` e é o healthcheck do compose;
   `GET /status/auth` exige `x-api-key`.

Nenhum segredo real consta neste diretório: o compose referencia variáveis e
o `.env.example` traz só placeholders óbvios. O `.env` real (copiado do
`.env.example` e preenchido fora do git) está coberto pelo `.gitignore`.

## Procedência da imagem (fixada em 2026-10-25)

| Serviço | Imagem fixada | Procedência |
|---|---|---|
| `baileys-api` | `ghcr.io/fazer-ai/baileys-api:v1.21.0@sha256:738477885d5e1f7a01a03a1940ee2292ec24bf634e3e2cf49ae11bfa19e0fb8e` | Repositório GHCR do vendor `fazer-ai` (workflow `publish_github_package.yml` do repo `fazer-ai/baileys-api`). Maior tag semântica estável listada no registry em 2026-10-25 (`latest` não usada). Digest do índice multi-arquitetura (amd64 + arm64). |
| `redis` | `redis:7-alpine@sha256:57e4255cc971b1c8d6f8a6ca283ac01bc3ecdd914273ef6bfaede87aaecd6541` | Docker Hub `library/redis`, tag `7-alpine`. Digest do índice multi-arquitetura. |

Comandos usados (somente leitura de metadados de registry; nenhuma camada baixada, nenhum container iniciado):

```sh
# lista de tags (token anônimo do GHCR)
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:fazer-ai/baileys-api:pull&service=ghcr.io" | sed -E 's/.*"token":"([^"]+)".*/\1/')
curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/fazer-ai/baileys-api/tags/list
# digests
docker buildx imagetools inspect ghcr.io/fazer-ai/baileys-api:v1.21.0
docker buildx imagetools inspect redis:7-alpine
```

Tentativas descartadas: `ghcr.io/chatwoot/baileys-api` responde `DENIED: invalid token`
(imagem inexistente ou privada), e `docker.io/chatwoot/baileys-api` retorna `object not found`.
O fork não usa fork de terceiro: a escolha segue o vendor que o provider Baileys espera.

**Autorização da versão:** a tag `v1.21.0` foi **autorizada pelo humano em 2026-10-25**
(a escolha da tag deixou de estar pendente). Ressalva: isto autoriza apenas a versão
fixada no manifesto. O **deploy não foi executado** e continua exigindo autorização
humana específica com servidor e escopo nomeados.

Ao atualizar a imagem, repetir os comandos acima, conferir a tag no registry e registrar
aqui a nova tag, o digest e a data.

## Procedimento de atualização de imagem (quando autorizado por humano)

1. Escolher a release/tag nova do baileys-api; anotar tag + digest:
   `docker buildx imagetools inspect <imagem>:<tag>`.
2. Editar `image:` em `docker-compose.yml` para `<imagem>:<tag>@sha256:<digest>`,
   conferindo o digest com `docker buildx imagetools inspect`.
3. Validar sintaxe SEM subir nada: `docker compose -f deploy/baileys-api/docker-compose.yml config`.
   Só renderiza. Exige `BAILEYS_REDIS_PASSWORD` no `.env` (ou no ambiente);
   sem ela o render falha com "required variable ... is missing". Para checar sem
   `.env` real, copie o manifesto e o `.env.example` para um diretório temporário
   e rode lá (feito assim na FORK-c9).
4. Subida, quando houver autorização humana com servidor/escopo nomeados:
   janela de manutenção, backup do volume `baileys-redis-data`, `pull` + `up -d`,
   checagem de `/status` e `/status/auth` (runbook T7.2), rollback para tag
   anterior em caso de falha.

## Arquivos

| Arquivo            | Papel                                                        |
|--------------------|--------------------------------------------------------------|
| `docker-compose.yml` | Manifesto dos serviços `baileys-api` + `redis` (Redis na rede interna sem portas; `baileys-api` com bind somente em `127.0.0.1:3025`) |
| `.env.example`       | Nomes das variáveis necessárias, sem valores reais           |
| `.gitignore`         | Garante que o `.env` preenchido nunca seja versionado        |
