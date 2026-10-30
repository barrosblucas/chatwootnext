# Stack E2E local (WP + fork Chatwoot)

Sobe a plataforma WhatsApp (`wp`) e o fork Chatwoot (`fork-web`, `fork-worker`) em
containers, reaproveitando os bancos e o baileys que já estão no projeto Docker
`connecta-e2e`. `wp` e `fork-web` estão publicados na LAN (`192.168.1.32`) para teste
de outro dispositivo; baileys, Redis e bancos continuam só em loopback.

**Aviso:** a exposição na LAN é só para teste com credenciais sintéticas. Não deixe
assim além do teste; volte para `127.0.0.1` quando terminar.

## Serviços e portas

| Serviço | Porta no host | Health |
|---|---|---|
| `wp` | 192.168.1.32:3005 (LAN) | `GET /health` |
| `fork-web` | 192.168.1.32:3006 (LAN; ou `FORK_WEB_HOST_PORT`) | `GET /api` |
| `fork-worker` | — (Sidekiq) | — |

Fora da LAN, sem publicação: `baileys-api` (127.0.0.1:3025), Redis e bancos.

Dependências fora deste compose (projeto `connecta-e2e`, rede `connecta-e2e-net`):
`connecta-e2e-wp-postgres-1`, `connecta-e2e-fork-postgres-1`, `connecta-e2e-wp-redis-1`,
`connecta-e2e-fork-redis-1`, `connecta-e2e-redis-1`, `connecta-e2e-baileys-api-1`.

## Subir

Pré-requisitos: as imagens locais `connecta-e2e-wp:local` e `connecta-e2e-fork:local`
e os containers de dados acima já existentes.

1. Crie `deploy/e2e/wp.env` e `deploy/e2e/fork.env` a partir de `.env.template`
   (valores reais; modo `600`). Eles são ignorados pelo git.
2. Na raiz do fork:

```sh
docker compose -p connecta-e2e -f deploy/e2e/compose.yml up -d
docker compose -p connecta-e2e -f deploy/e2e/compose.yml ps
```

Verificação: `curl -s -o /dev/null -w '%{http_code}' http://192.168.1.32:3005/health` → `200`;
`curl -s -o /dev/null -w '%{http_code}' http://192.168.1.32:3006/api` → `200`.
O primeiro acesso ao Chatwoot pela LAN pode levar ~20 s (aquecimento do Vite em dev).

## Resetar

Os dados (bancos, Redis, storage do fork) estão em volumes nomeados. Para zerar:

```sh
docker compose -p connecta-e2e -f deploy/e2e/compose.yml down
docker volume rm connecta-e2e_fork_storage
```

Os bancos e o baileys estão em outro projeto. Apagar os volumes `connecta-e2e_wp_pgdata`,
`connecta-e2e_fork_pgdata`, `connecta-e2e_wp_redis*`, `connecta-e2e_fork_redis*` e
`connecta-e2e_baileys-redis-data` **apaga os dados de teste**. Faça isso só por decisão
explícita.

## Avisos

- `wp.env` e `fork.env` contêm segredos e **não entram no git** (`.gitignore` local).
  Nunca cole valores reais em `.env.template`, em commits ou em logs.
- Nenhum valor de exemplo é um segredo válido. Os valores de teste ficam só na sua máquina.
- A chave `BAILEYS_PROVIDER_DEFAULT_API_KEY` precisa existir no Redis do baileys
  (`@baileys-api:api-keys:<chave>`). Registro: `bun scripts/manage-api-keys.ts create user <chave>`
  dentro do container `connecta-e2e-baileys-api-1`.
- Os containers de dados não são recriados por este compose (eles são externos e marcados com
  `restart: unless-stopped` diretamente).
- `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` (em `fork.env`) libera webhooks para rede privada
  (ex.: WordPress na LAN). **Somente e2e local.** Não vale para produção: lá deve permanecer
  `false` ou ausente (`lib/safe_fetch.rb`).

## Dados de teste (semeados em 2026-10-25)

Senhas ficam só em `deploy/e2e/.env` (ignorado): `E2E_ADMIN_PASSWORD`, `E2E_AGENT_PASSWORD`.

Fork (`chatwoot_e2e`):
- conta `accounts.id=1` ("Conecta E2E"); inbox `inboxes.id=1` (Atendimento Humano E2E, `Channel::Whatsapp`)
- usuários `users.id`: 1 admin@e2e.local, 2 agent@e2e.local, 3 agent2@e2e.local
- unidades (`connecta_org_units`): `e2e00000-0000-4000-8000-000000000001` Prefeitura E2E, `...0002` Secretaria de Saúde, `...0003` Recepção, `...0004` Setor A
- escopo: `connecta_scoped_inboxes` inbox 1 `enforce`; grants `atender`+`transferir` para 2 e 3 em `...0004`

Plataforma (`connecta_e2e`):
- `org_units` (4), `staff_users` (3: admin@e2e.local `municipal_admin`; agent@ e agent2@ `operator`), `staff_grants` (4 ativos), `staff_identity_links` (3 ativos: staff ↔ `chatwoot_account_id=1`, `chatwoot_user_id` 1/2/3)

Integração Chatwoot no WP (`wp.env`, já configurada): `CHATWOOT_ENABLED=true`, `HUMAN_HANDOFF_PROVIDER=chatwoot`, `CHATWOOT_WEBHOOK_SECRET`, `CHATWOOT_API_ACCESS_TOKEN`, `CHATWOOT_INBOX_ID=1`. Pendente: `CHATWOOT_INBOX_IDENTIFIER` ainda é placeholder (a inbox 1 é `Channel::Whatsapp` e não tem identifier).

Dados sintéticos criados durante os testes (podem ser apagados): contato `contacts.id=1` ("Cidadão E2E"), conversa `conversations.id=1` (display_id 1), `contact_inboxes.id=1`, e 3 linhas em `inbox_members` (inbox 1). Para o teste real, use uma conversa criada pela interface, não estes dados.

## Teste real com número

Objetivo: mandar uma mensagem do celular para o número de atendimento humano e ver a plataforma reagir.

URLs:
- Chatwoot (fork): `http://192.168.1.32:3006` (`FRONTEND_URL` em `fork.env`)
- Painel da plataforma (Next, serviço `wp-admin`): `http://192.168.1.32:3007/login` (API em `wp`:3005, rota `/admin/api/staff-auth/login`)

Logins: `admin@e2e.local`, `agent@e2e.local` e `admin@bandeirantes.ms.gov.br` (admin municipal, vinculado ao usuário Chatwoot 4 na conta 1). As senhas ficam só em `deploy/e2e/.env` ou no gerenciador do operador. Não copie senhas para este arquivo.

Passo a passo:
1. Entre no Chatwoot com `admin@e2e.local`.
2. Crie uma inbox do tipo **WhatsApp**, com provider **Baileys** e o número real de teste.
3. Escaneie o QR code que aparece na inbox com o celular.
4. Envie uma mensagem do celular para esse número (ex.: "Oi, preciso de atendimento").
5. Confira a conversa aparecendo na inbox nova.

O que observar depois:
- um caso novo em `attendance_cases`, com protocolo;
- a sessão de recepção saindo de `activating` (`reception_sessions`);
- a mensagem de triagem enviada de volta ao celular.

Conferir o id da inbox nova:

```sh
docker exec connecta-e2e-fork-postgres-1 psql -U chatwoot -d chatwoot_e2e -c 'select id, name, channel_type from inboxes;'
```

Depois de criar a inbox, atualize `HUMAN_SERVICE_INBOX_ID` em `deploy/e2e/wp.env` com o id novo, e recrie o `wp`:

```sh
docker compose -p connecta-e2e -f deploy/e2e/compose.yml up -d --force-recreate wp
```

## Permissão para criar inbox WhatsApp

- O admin de teste precisa do grant `admin_nominal` em `connecta_user_grants` (unidade da conta) para criar inbox WhatsApp; sem ele o guard `connecta_scope_inbox_create_guard!` nega com 403.
- `POST /api/v1/accounts/:id/inboxes` responde **200** quando cria a inbox (comportamento nativo do Chatwoot).
- O grant já está aplicado ao `admin@bandeirantes.ms.gov.br` (usuário 4, conta 1).
