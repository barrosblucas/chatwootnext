# Runbook — contingência do número humano (T7.3)

Estado: **NÃO EXECUTADO** — documento operacional. Nada foi rodado, desligado
ou trocado. Qualquer passo de execução exige homologação (T8.1) e autorização
humana com servidor/escopo nomeados.

## Flags REAIS (verificadas no código — use estes nomes, sem inventar)

Fork (chatwootnext), verificados por grep em `app/`:

| Flag / campo | Onde | Efeito real |
|---|---|---|
| `CONNECTA_HUMAN_NUMBER_ENABLED` (`false` padrão) | `app/services/connecta/runtime/feature.rb:3` | Opt-in do modo número humano; `false` = comportamento legado |
| `CONNECTA_ACCOUNT_ID` (obrigatória) | `feature.rb:7` | Conta do piloto; receptor recusa 403 se divergente |
| `CONNECTA_PLATFORM_URL` + `CONNECTA_FORK_TO_PLATFORM_SECRET` | `runtime/platform_client.rb:13` | Fork → WP (destinos, prepare/commit/abort/activated, identity, revogações) |
| `CONNECTA_PLATFORM_TO_FORK_SECRET` | `connecta/v1/base_controller.rb:16` | WP → fork (sync/heartbeat, revoke, activate) |
| `CONNECTA_DISPATCH_WAIT_MS` (0–30000, padrão 5000) | `runtime/transfer_transaction.rb:138` | Espera por despacho antes de transferir |
| `CONNECTA_ACL_HEARTBEAT_TTL_SEC` (padrão 60) | `runtime/g0_adapter.rb:62` | TTL do heartbeat fail-closed da ACL |
| `CONNECTA_RECEPTION_ORG_UNIT_ID` | `runtime/reception_scope_creator.rb:12` | Unidade de recepção; ausente com inbox marcada = erro explícito |
| `ScopedInbox.enforcement` (`enforce`/`admin_only`) + `maintenance` (bool) | `models/connecta/scoped_inbox.rb`, migration `...human_number_tables.rb:9` | `admin_only` = servidor nega toda superfície a não-admin; `maintenance` = entradas gravadas, envio humano bloqueado |

WP (whatsapp-platform), verificados em `apps/whatsapp-platform/src/config.ts`:

| Flag | Onde | Efeito real |
|---|---|---|
| `HUMAN_SERVICE_MODE` (`meta_relay` \| `external_number`) | `config.ts:146,1450` | Modo por stack; virada para `external_number` exige `HUMAN_SERVICE_NUMBER`, `HUMAN_SERVICE_INBOX_ID`, `HUMAN_SERVICE_RECEPTION_UNIT_ID` |
| `HUMAN_SERVICE_NUMBER` | `config.ts:153,1460` | Número humano da stack (E.164) |
| `HUMAN_SERVICE_INBOX_ID` | `config.ts:147–151,1472` | Inbox(es) do número humano |
| `HUMAN_SERVICE_RECEPTION_UNIT_ID` | `config.ts:154` | Unidade de recepção da stack |
| `ATTENDANCE_ADMISSION_MODE` (`shadow` \| `enforce`) | `config.ts:152` | Admissão única; em stack com modo novo, voltar a `shadow` reabre corrida |
| `STAFF_AUTH_MODE` (`shared_token` \| `individual`) | `config.ts:151` | Em stack piloto, `shared_token` nunca lê dados `human_number`/org |
| `CONNECTA_ACL_HEARTBEAT_MAX_AGE_SEC`, `CONNECTA_DISPATCH_WAIT_MS`, `CONNECTA_PLATFORM_TO_FORK_SECRET`, `CONNECTA_FORK_TO_PLATFORM_SECRET` | `config.ts:156–159` | Contrapartes WP do contrato de fio v1 |

> PENDÊNCIA REGISTRADA: não existe no fork variável `CONNECTA_BAILEYS_URL`
> (ver README do `deploy/baileys-api/`). O transporte é endereçado por
> `BAILEYS_PROVIDER_DEFAULT_URL` + `BAILEYS_PROVIDER_DEFAULT_API_KEY`.

## 1. Ordem dos passos (contingência do número)

1. **Desligar o CTA** (WP, stack afetada): `HUMAN_SERVICE_MODE=meta_relay`
   (volta ao relay legado; novos pedidos NÃO vão para CTA). Confirmar que o bot
   segue utilizável sem acionar handoff novo.
2. **Contenção no fork**: marcar a inbox física `maintenance = true`
   (entradas continuam gravadas; envio humano bloqueado; cidadão recebe aviso
   conforme Q-13) e pausar o despacho da inbox física (`parked`, sem descarte).
   Se houver falha grave com dados novos: `enforcement = 'admin_only'`
   (servidor nega toda superfície a não-admin, inclusive equipe/bot/anexos/
   contatos/busca — §14.3 do plano; proibido "tirar membros e desligar ACL").
3. **Aviso aos casos abertos**: mensagem do número humano (admin auditado)
   informando instabilidade e canal alternativo; registrar protocolo de cada
   caso avisado. Casos abertos **seguem no número humano até encerrar** —
   nunca mover casos de canal.
4. **Conciliar**: outbox, despachos `uncertain`, transferências
   `committed_local`/`activation_stuck`, admissões e casos abertos, com relatório.
5. **Troca de número** (se decidida): parear o novo número (QR só com admin,
   runbook T7.2 §6), atualizar `HUMAN_SERVICE_NUMBER` (WP) e o setup da conexão
   (`/connections/:phone`) no baileys-api, validar `/status` + `/status/auth`
   do novo número, re-testar ponta a ponta sintética antes de religar o CTA.
6. **Religar**: só após T8.1 verde no novo número — `HUMAN_SERVICE_MODE=
   external_number`, inbox física fora de `maintenance`, acesso escopado
   reaberto após negativos de G1 verdes.

Campo de evidência: [ ] cada passo com data/hora + operador + protocolo(s): ____

## 2. O que preservar (nunca apagar)

- Conversas da inbox física, anexos (inclusive links antigos), contatos e
  resultados de busca já gravados — rollback nunca apaga dados (§14.3).
- Schema `connecta_*`: sem `DROP`; flags off apenas ignoram colunas/tabelas.
- Casos `human_number` abertos: continuam no número humano até encerrar,
  por admin auditado.
- Auditoria de transferências, revogações e ativações (conciliação do passo 4).
- Remover membros da inbox **não** garante "só admin" (a política nativa
  também libera por `team_access?` e `agent_bot?`); em falha grave usar
  `enforcement='admin_only'`, nunca "tirar membros e desligar ACL".

Campo de evidência: [ ] inventário de preservação conferido por: ____ em: ____

## 3. Como voltar (retorno ao normal)

1. Corrigir a causa (sessão, quorum do provider, configuração) com versão
   compatível que **mantenha** o enforcement (`admin_only`/`read_only` nunca
   sai enquanto houver dados novos).
2. Re-testar negativos de G1 (ACL, anexo antigo, revogação, worker atrasado).
3. Tirar a inbox de `maintenance`, reabrir acesso escopado por papel.
4. Religar o CTA (`HUMAN_SERVICE_MODE=external_number`) por último, após o
   gate Q-1 e os gates 15.2.
5. Relatório diário de sinais (§12 do plano) por no mínimo 1 ciclo do piloto.

Campo de evidência: [ ] retorno autorizado por: ____ · testes G1 verdes em: ____

## 4. O que NÃO fazer

- Não apagar conversas/anexos/contatos para "limpar" a contingência.
- Não mover casos abertos para outro canal ou número.
- Não voltar `ATTENDANCE_ADMISSION_MODE` para `shadow` em stack com modo novo
  ativo ou casos `human_number` abertos (reabre a corrida legado × novo).
- Não reverter ACL/enforcement enquanto a inbox física existir.
- Não permitir `STAFF_AUTH_MODE=shared_token` em stack que já teve dados do
  modo novo (painel de gestor vai para manutenção; admin geral pelo acesso auditado).
- Não expor QR ou status de conexão a agente/gestor durante a contingência.
