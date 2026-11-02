# Runbook — saúde e reconexão do baileys-api (T7.2)

Estado: **NÃO EXECUTADO** — documento operacional. Nada foi rodado nem implantado.
Pré-requisito: T7.1 (`deploy/baileys-api/`).

Fontes verificadas no fork: `app/services/whatsapp/providers/whatsapp_baileys_service.rb`
(`self.status` → `GET /status` com `x-api-key`; `validate_provider_config?` →
`GET /status/auth`; `rejected_session?` após 3 ciclos de quarentena),
`app/services/whatsapp/baileys_handlers/connection_update.rb`
(valores `close/connecting/reconnecting/open`, quarentena, `reachoutTimeLock`,
epoch anti-stale), `app/listeners/action_cable_listener.rb` (QR/erro só para admin).

## 1. Checagem de `/status` e `/status/auth`

Pré-condição: acesso à rede interna do compose + `BAILEYS_PROVIDER_DEFAULT_API_KEY`
em mãos (nunca em log, ticket ou print compartilhado).

```sh
BASE="$BAILEYS_PROVIDER_DEFAULT_URL"   # ex.: http://baileys-api:3000 (rede interna)
KEY="$BAILEYS_PROVIDER_DEFAULT_API_KEY"

# 1a. Serviço de pé?
curl -sS -o /dev/null -w '%{http_code}\n' -H "x-api-key: $KEY" "$BASE/status"
# Esperado: 200. Qualquer 5xx/timeout = serviço fora (ir para §4).

# 1b. Credenciais/autorização válidas?
curl -sS -H "x-api-key: $KEY" "$BASE/status/auth"
# Esperado: 2xx com payload de auth. 401/403 = chave errada ou sessão não autorizada.
```

> **Redis novo (confirmado no ensaio do zero 2026-11-02):** com volume Redis recriado, NENHUMA chave existe e `/status/auth` devolve `401 {"error":"Unauthorized","message":"Valid API key required"}` mesmo com a chave correta no `.env`. Registrar antes de qualquer diagnóstico:
> ```sh
> docker exec <baileys-api> bun scripts/manage-api-keys.ts create user "$BAILEYS_API_KEY"
> ```
> (chaves vivem em `@baileys-api:api-keys:<chave>` no Redis, `{"role":"user"}`; ver `scripts/manage-api-keys.ts` na imagem).

Campo de evidência: [ ] data/hora: ____ · `/status` → HTTP ____ · `/status/auth` → HTTP ____ · operador: ____

## 2. Sinais de desconexão e quarentena (o que observar)

No fork, observar `provider_connection` do canal (inbox física) e os webhooks
`connection.update` / `reconnect_loop_detected`:

| Sinal | Onde aparece | Significado |
|---|---|---|
| `connection: close` | `provider_connection.connection` | Nunca abriu ou fechou sem condição de envio/recebimento |
| `connection: connecting` | idem | Pareando; esperando leitura de QR (admin) |
| `connection: reconnecting` | idem | Sessão existia, mas socket não está `open` (link inicial, restart do baileys-api) |
| `connection: open` | idem | Saudável: pronto para enviar/receber |
| `error` preenchido | `provider_connection.error` + log `Baileys connection error:` | Causa traduzida via i18n (`provider_connection.*`); investigar |
| `quarantine: {strikes, until}` | `provider_connection.quarantine` (só via `reconnect_loop_detected`) | baileys-api colocou o número em quarentena após ciclo de reconnect falho; `until` = próxima tentativa |
| `reachoutTimeLock: {is_active, time_enforcement_ends, enforcement_type}` | `provider_connection.reachout_time_lock` | Restrição de contato ativo (com debounce ~60 s do provider); `isActive:false` = liberado |
| `strikes >= 3` sem `open` | `rejected_session?` | Sessão considerada morta: próximo `setup_channel_provider` descarta a sessão antes de parear QR novo |
| `epoch` menor que o gravado | log `Baileys stale connection.update discarded` | Evento tardio de instância antiga (failover); descartado corretamente, sem ação |

Campo de evidência: [ ] `connection`: ____ · `error`: ____ · `quarantine`: ____ · `reachout_time_lock`: ____ · `epoch`: ____

## 3. Janela de alerta

- Transição para `close`/`reconnecting` fora de janela de manutenção → alerta imediato.
- `quarantine.strikes >= 1` → atenção (primeira quarentena); `>= 3` → crítico
  (sessão será descartada no próximo setup; preparar pareamento com admin).
- `reachoutTimeLock.is_active: true` → avisar operação (restrição de envio pode
  travar respostas do piloto); registrar `time_enforcement_ends`.
- Ausência de `connection.update` por mais de 5 min com tráfego esperado → checar §1.
- **Não** abrir chamado para "evento stale descartado" isolado: é o anti-stale
  funcionando (failover entre instâncias do provider).

Campo de evidência: [ ] alerta aberto (id/canal): ____ · severidade: ____ · horário: ____

## 4. Procedimento de reinício do serviço

Ordem (quando houver autorização humana com servidor/escopo nomeados):

1. Confirmar janela e avisar: casos abertos seguem no número humano; novas
   entradas continuam gravadas; envio pode pausar (ver runbook T7.3 se for
   contingência de número, não só restart técnico).
2. Checar §1 antes (registrar baseline) e anotar `connection` atual no fork.
3. Reiniciar SOMENTE o serviço autorizado (ex.: `docker compose restart baileys-api`
   no servidor nomeado na autorização — comando ilustrativo, NÃO executado aqui).
4. Aguardar `start_period` do healthcheck; repetir §1 (`/status` 200, `/status/auth` 2xx).
5. No fork: aguardar `connection.update` com `connection: open` (ou `reconnecting`
   transitório). Se voltar `connecting` + QR: **somente admin** faz o pareamento (§6).
6. Se `quarantine.strikes >= 3` e não abrir: o próximo setup descarta a sessão
   (`rejected_session?`) e exige QR novo — escalar para admin antes de forçar.
7. Registrar evidências (§1–§2) e encerrar o alerta.

Campo de evidência: [ ] reinício autorizado por: ____ · início: ____ · fim: ____ · `connection` final: ____

## 5. Critérios de escalonamento

- `open` não retorna em 15 min após reinício autorizado → escalar para operação + admin do piloto.
- 3+ ciclos de quarentena (`strikes >= 3`) → escalar: provável sessão morta, pareamento novo.
- `reachoutTimeLock` ativo travando o piloto → escalar para decisão de janela/mensagem.
- Qualquer suspeita de sessão sequestrada (número `open` em instância desconhecida,
  `epoch` incoerente persistente) → escalar imediatamente; NÃO tentar "re-importar"
  sessão por conta própria.
- Falha que atinge casos abertos ou exige troca de número → acionar runbook T7.3
  (`connecta-numero-contingencia.md`).

Campo de evidência: [ ] escalado para: ____ · motivo: ____ · horário: ____

## 5.1 Paridade de env: TTL do heartbeat ACL (fork × plataforma)

- Regra: `CONNECTA_ACL_HEARTBEAT_TTL_SEC` (fork) deve ser **igual** a
  `CONNECTA_ACL_HEARTBEAT_MAX_AGE_SEC` (plataforma WP).
- Valor atual: **120 s** nos dois lados (padrão do fork em
  `app/services/connecta/scope/projection.rb:10`; padrão do WP em
  `apps/whatsapp-platform/src/config.ts:156`, `parseBoundedInt(..., 120, 30, 3600)`).
- Motivo: o WP envia heartbeat a cada `aclHeartbeatMaxAgeSec/3` (40 s;
  `apps/whatsapp-platform/src/services/humanService/runtime.ts:62`). O fork usa o
  mesmo valor como janela de validade da projeção (decisão 003).
- **Sintoma se divergir:** se o fork tiver TTL menor que o WP, a projeção expira
  entre heartbeats e o fork **nega acesso escopado** mesmo com o WP saudável.
  Sintoma visível: usuários do escopo perdem conversas e recebem 403/404 de forma
  intermitente, com a plataforma em `open`.
- Verificação (somente leitura, sem alterar env): comparar o valor efetivo dos
  dois `.env` com acesso autorizado, sem copiar os valores para o ticket.

Campo de evidência: [ ] TTL fork: ____ s · MAX_AGE WP: ____ s · iguais: sim/não · operador: ____

## 5.2 Pré-requisito de autorização para (re)parear (`admin_nominal`)

- Em inbox marcada `enforce`, `setup_channel_provider` (QR novo), `disconnect` e a criação de inbox WhatsApp passam pelo guard Connecta (`app/services/connecta/scope/inbox_hook.rb`), que exige `Projection#admin?` = usuário verificado + grant `admin_nominal`. O papel nativo `administrator` sozinho é negado com 403 (o modal "Vincular dispositivo" dispara o setup sozinho ao abrir e mostra o 403).
- O sync ACL do bot nunca cria esse grant (só `acompanhar`/`atender`/`transferir`); sem rotina oficial, o bootstrap é manual no banco de teste (idempotente, sem tocar no provedor; ver `deploy/e2e/README.md` § "Permissão para criar inbox WhatsApp" e o roteiro de implantação do número humano §B):
```sh
docker exec <rails> bin/rails runner 'u=User.find(<ADMIN_USER_ID>); puts Connecta::Scope::Projection.new(u).admin?'
# esperado: true antes de abrir o modal; false para agente
```
- O `qr_data_url` com `qr_updated_at` antigo e `connection=close` é obsoleto: nunca parear QR antigo — abrir o modal com o grant válido faz nascer QR fresco.

Campo de evidência: [ ] `Projection#admin?` do operador: ____ · `qr_updated_at`: ____ · operador: ____

## 6. O que NÃO fazer (proibido)

1. **NUNCA expor QR (`qr_data_url`) a agente ou gestor** — QR + `status` de conexão
   são admin-only no fork (`action_cable_listener.rb`, `provider_connection_data`).
   Vazamento permite sequestro da sessão do número humano.
2. Não compartilhar `BAILEYS_PROVIDER_DEFAULT_API_KEY`, `import-session` ou
   `webhook_verify_token` em ticket, print, log ou chat.
3. Não publicar porta do baileys-api/Redis para fora da rede interna.
4. Não forçar `DELETE /connections/:phone` nem re-importar sessão sem autorização
   e sem admin presente (destrói pareamento e derruba o número).
5. Não confundir `reconnecting` transitório (pós-restart) com sessão morta:
   só `strikes >= 3` sem `open` caracteriza `rejected_session?`.
6. Não herdar segredos `CONNECTA_*` do shell: segredos CONNECTA_* devem vir de um arquivo de ambiente (--env-file) comum, nunca herdados do shell; recriar rails/sidekiq com valores diferentes do bot causa 401 na ativação e protocolo nunca anunciado (ensaio 2026-11-02: `POST /connecta/v1/scopes/3/activate` 401 → 200 após `--env-file`, escopo `active`).
