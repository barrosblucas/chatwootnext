# 006 — HTTPS só no ensaio LAN via proxy Caddy dedicado (sem tocar produção)

## Contexto
Gravador/microfone exigem contexto seguro; o ensaio roda em `http://192.168.1.32` (IP puro, sem DNS). Produção (192.168.1.39), DNS público, firewall, instalação global, dados e migrações estão fora de escopo. Chatwoot (3000) e painel Saude (6700) têm binds só na LAN; portas 3443/3444 livres; openssl 3.5.5 disponível; Caddy ausente; certutil ausente; NSSdb do usuário existe.

## Decisão
1. **Proxy `tls-proxy` dedicado ao ensaio** (`docker-compose.teste-lan.tls.yml`): Caddy oficial 2.11.7 com tag+digest fixados (`caddy:2-alpine@sha256:e70b...`); binds host SOMENTE `192.168.1.32:3443→rails:3000` e `:3444→wb-saude-admin:6700`; HTTP legado 3000/6700 intacto; recursos conservadores (128m/0.5cpu); sem Docker socket, sem privileged; redes `chatwootnext_default` + externa `wb-saude_default`.
2. **CA local + cert SAN-IP** em `deploy/ensaio-tls/certs/` (ignorado, 0700/0600, nunca commitado/impresso): proxy monta SÓ server crt/key readonly, nunca a chave da CA. `auto_https off`, `admin off`, sem ACME.
3. **`FRONTEND_URL=https://192.168.1.32:3443`** em rails+sidekiq (parametrizada com defaults do ensaio; sem credenciais/município); `FORCE_SSL` segue false (health HTTP legado preservado); `CONNECTA_PLATFORM_URL`/ADMIN internos HTTP inalterados; proxy envia `Host` + `X-Forwarded-Proto: https` (+ porta).
4. **Trust real do navegador, sem enfraquecer segurança**: import da CA pública no NSS do usuário (`C,,`); sem trust global de SO, sem `--ignore-certificate-errors`, sem desligar validação TLS; sem manipular Chrome via DevTools nesta etapa.
5. **Rollback restrito** a proxy/FRONTEND_URL/trust (`deploy/ensaio-tls/README.md`), sem tocar volumes.

## Consequências
- Novos: `docker-compose.teste-lan.tls.yml`, `deploy/ensaio-tls/{Caddyfile,README.md}`; `.gitignore` ignora `deploy/ensaio-tls/certs/`.
- Subida/recriação sempre com os 4 composes + `--env-file .env.connecta-ensaio`, `--no-deps`, sem build/migrate/down -v.
- Imagem de ensaio vigente segue sem o build da mídia protegida (deploy é a próxima etapa; nada aqui alega correção na imagem antiga).

## Alternativas consideradas
- `bind 192.168.1.32` dentro do Caddyfile: rejeitado; o IP da LAN não existe na netns do container — o bind restrito é na publicação de portas do Compose (lado host).
- `FORCE_SSL=true`: rejeitado; quebraria o health HTTP legado e mudaria comportamento além do ensaio.
- Trust global de SO ou flag que desliga verificação TLS: rejeitado; enfraquece a VM fora do ensaio.
