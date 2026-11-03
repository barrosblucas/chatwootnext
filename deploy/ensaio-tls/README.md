# TLS de ensaio — Chatwoot (3443) + painel (3444) na LAN 192.168.1.32

Runbook da microetapa HTTPS SOMENTE na VM de ensaio. Não toca produção
(192.168.1.39), DNS público, firewall, instalação global, dados ou migrações.

## Arquivos

| Arquivo | Papel |
|---|---|
| `../../docker-compose.teste-lan.tls.yml` | Override: `FRONTEND_URL=https://192.168.1.32:3443` em rails+sidekiq; serviço `tls-proxy` (Caddy oficial 2.11.7, tag+digest fixados, binds só LAN, recursos conservadores, sem socket/privileged) |
| `Caddyfile` | Proxy: `:3443 → rails:3000`, `:3444 → wb-saude-admin:6700`; `tls` com cert local; `Host` + `X-Forwarded-Proto: https` ao upstream; `auto_https off`, `admin off` |
| `certs/` | **IGNORADO pelo git** (`.gitignore`): `ensaio-ca.crt` (CA pública), `ensaio-ca.key` (**só assinar; nunca montar no proxy**), `ensaio-server.crt/key` (montados readonly no proxy) |

Nenhum conteúdo de cert/chave é copiado para Markdown, log ou relatório.

## Subir (sempre com o envfile comum; nunca imprimir valores)

```sh
cd /home/thanos/chatwootnext
docker compose --env-file .env.connecta-ensaio -p chatwootnext \
  -f docker-compose.teste-lan.yml \
  -f docker-compose.teste-lan.baileys-override.yml \
  -f docker-compose.teste-lan.human-number-override.yml \
  -f docker-compose.teste-lan.tls.yml \
  up -d --no-deps tls-proxy
# FRONTEND_URL exige recriar rails/sidekiq (SEM build, SEM migrate, SEM down -v):
docker compose --env-file .env.connecta-ensaio -p chatwootnext \
  -f docker-compose.teste-lan.yml \
  -f docker-compose.teste-lan.baileys-override.yml \
  -f docker-compose.teste-lan.human-number-override.yml \
  -f docker-compose.teste-lan.tls.yml \
  up -d --no-deps rails sidekiq
```

## Validar (sem `-k`, sem query token)

```sh
CA=/home/thanos/chatwootnext/deploy/ensaio-tls/certs/ensaio-ca.crt
CRT=/home/thanos/chatwootnext/deploy/ensaio-tls/certs/ensaio-server.crt
openssl verify -CAfile "$CA" "$CRT"
openssl x509 -in "$CRT" -noout -subject -issuer -dates -ext subjectAltName
curl --cacert "$CA" -o /dev/null -w '%{http_code}\n' https://192.168.1.32:3443/health
curl --cacert "$CA" -o /dev/null -w '%{http_code}\n' https://192.168.1.32:3444/login
curl -o /dev/null -w '%{http_code}\n' http://192.168.1.32:3000/health   # legado intacto
curl -o /dev/null -w '%{http_code}\n' http://192.168.1.32:6700/login    # legado intacto
```

## Callback interno Baileys (obrigatório com CA local)

Separação: `FRONTEND_URL=https://192.168.1.32:3443` (override TLS) segue como
endereço PÚBLICO (navegador/bot via `tls-proxy`); o callback registrado no
transporte Baileys usa `INTERNAL_HOST_URL=http://rails:3000` via rede interna
`baileys-edge` (HTTP sem TLS). Motivo: o transporte Baileys não confia na CA
local do ensaio — callback `https://LAN:3443` falha com
`unable to verify the first certificate` e o ingresso nunca chega ao Rails.

Mecanismo existente (sem código novo): `Inbox#callback_webhook_url`
(`app/models/inbox.rb`) usa `INTERNAL_HOST_URL` quando
`Channel::Whatsapp#use_internal_host?` (`BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL`
em `app/models/channel/whatsapp.rb`); o `BaileysConnectionCheckJob` reescreve o
`webhookUrl` no transporte no ciclo normal (~5min via `TriggerScheduledItemsJob`).
Ruby trata qualquer string não vazia como truthy (inclusive `"false"`):
habilitar só com `"true"` explícito em rails E sidekiq; desligar no futuro é via
unset, nunca `"false"`. `verify_token`/autenticação preservados; só scheme/host
do callback muda para o interno (`http://rails:3000` +
`/webhooks/whatsapp/<template-sem-telefone>`).

Validar (só scheme/host/port + template de path, nunca valor completo):

```sh
docker exec chatwootnext-rails-1 printenv FRONTEND_URL INTERNAL_HOST_URL BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL
docker exec chatwootnext-sidekiq-1 printenv FRONTEND_URL INTERNAL_HOST_URL BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL
```

## Confiança no navegador do humano (workstation própria)

A CA de ensaio (`certs/ensaio-ca.crt`, caminho publicado no relatório da etapa)
só é válida nesta LAN. Para confiar nela **no seu computador** (nunca na VM além
do trust NSS local já feito):

- **Firefox (qualquer SO):** Configurações → Privacidade e Segurança →
  Certificados → Ver certificados → Autoridades → Importar → selecione a CA →
  marque “Confiar para identificar sites”.
- **Chrome/Edge no Windows:** `Win+R → certmgr.msc` → Autoridades de
  Certificação Raiz Confiáveis → Certificados → Importar (Conta de Usuário atual,
  nunca Máquina Local) → reinicie o navegador.
- **Chrome no Linux:** `certutil -d sql:$HOME/.pki/nssdb -A -n "Ensaio LAN" -t "C,," -i ensaio-ca.crt`
- **Chrome/Safari no macOS:** abra a CA no Acesso às Chaves → login (nunca
  Sistema) → Sempre Confiar para SSL.

Depois: `https://192.168.1.32:3443` e `https://192.168.1.32:3444` sem aviso.
O microfone/gravador (getUserMedia) segue exigindo contexto seguro: funciona no
HTTPS, continua bloqueado em `http://IP`.

## Rollback restrito (só proxy/FRONTEND_URL/trust; sem tocar volumes)

1. `docker compose -p chatwootnext stop tls-proxy` (ou `rm tls-proxy`).
2. Recriar rails/sidekiq **só com os 3 composes originais** (sem o `.tls.yml`):
   `FRONTEND_URL` volta a `http://192.168.1.32:3000`.
   Restrito aos dois env overrides (`INTERNAL_HOST_URL`,
   `BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL`) + recriação de rails/sidekiq;
   sem volume/DB/QR. Não aplicar rollback do callback automaticamente para
   voltar ao estado TLS quebrado, salvo regressão de saúde mais grave.
3. Trust NSS local (se feito): `certutil -d sql:$HOME/.local/share/pki/nssdb -D -n "<apelido>"`.
4. Chaves: apagar `certs/` se a etapa for descartada. Nada em volumes/dados muda.

## Limites desta etapa

- A imagem de ensaio vigente no runtime ainda **não** contém o build com a mídia
  protegida/frontend recente: nada aqui alega mídia corrigida na imagem antiga;
  o deploy de código é a próxima microetapa.
- Sem `FORCE_SSL` (proposital): o Rails continua aceitando HTTP legado; o
  endurecimento (HSTS/redirect) fica para decisão futura, fora do ensaio.
