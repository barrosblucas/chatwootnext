# EVID4 — Acesso a anexos de canal Baileys (T0.4)

- Data (UTC): 2026-10-22, de 15:52Z a 15:58Z.
- Alvo: máquina local, worktree `chatwootnext-connecta-g0-prep`, Postgres `127.0.0.1:55432/conecta_baileys_g0_test`, Redis `127.0.0.1:56379`, projeto `conecta-baileys-g0-test`. Dados sintéticos.
- Medição: request specs sem sessão e sem token de usuário; storage de teste (Disk); sem rede externa.
- Estado do gate: **G0 ABERTO**. Esta evidência não aprova ACL, transporte nem Fase 1.

## 1. Execução

Comando (launcher com guard antes do Rails):

```
PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH \
  scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/attachment_access_spec.rb spec/connecta/agent_bot_delivery_spec.rb
```

| Rodada | Exit | Resultado | Log |
|---|---|---|---|
| 1 (antes da edição de spec) | 0 | 28 exemplos (11 anexos + 17 AgentBot), 0 falhas | `05-logs/run-1-specs.log` |
| 2 (depois da 1ª edição) | 0 | 29 exemplos (12 anexos + 17 AgentBot), 0 falhas | `05-logs/run-2-specs.log` |
| 3 (repetição) | 0 | 29 exemplos, 0 falhas | `05-logs/run-3-specs.log` |
| 4 (depois da correção do timeout) | 0 | 29 exemplos, 0 falhas | `05-logs/run-4-specs.log` |
| 5 (repetição final) | 0 | 29 exemplos, 0 falhas | `05-logs/run-5-specs.log` |

Rodadas 4 e 5 são as finais. A rodada 1 é a linha de base do que existia antes da mudança.

- Pré-condições do launcher: 11 itens `ok` (contexto Docker local, Ruby 3.4.4, sem Dotenv na raiz, alvo do banco G0, Docker, recursos do projeto, containers em execução, Postgres e Redis escutando, segredo 0600, schema esperado). Nenhum `falta`.
- O guard `Connecta::G0TargetGuard.verify!` roda antes de `require 'rails_helper'` em cada spec.
- Specs de `Webhooks::Trigger` e `AgentBots::WebhookJob` existentes não foram executadas: a allowlist do launcher aceita só `spec/connecta/` e `spec/requests/connecta/`. Liberá-las exige mudar o runner, fora de escopo.

## 2. Mudanças nas specs (sem mudança de app)

- `attachment_access_spec.rb`: comentário corrigido (os blobs são apagados no `after`; o diretório `tmp/storage` permanece). Novo exemplo: o serviço de blob do ambiente de teste é `ActiveStorage::Service::DiskService`.
- `agent_bot_delivery_spec.rb`: (a) asserção de `Content-Type: application/json` no teste de corpo e assinatura; (b) o exemplo de timeout agora drena a fila (`perform_enqueued_jobs` sem `at:`). Antes, ele só rodava até `base_time` e não provava ausência de retry. Nenhuma outra alteração.

Baseline antes da mudança: `05-baseline-sha256.txt` e cópias em `05-baseline-arquivos/`.

## 3. Observado (o que o app entrega hoje)

Fonte do código: `app/models/attachment.rb`. Medido pelos exemplos indicados.

| Item | Observado | Exemplo que prova |
|---|---|---|
| `file_url` | `url_for(file)`: `/rails/active_storage/blobs/redirect/<signed_id>/<arquivo>`. Não expira: o `signed_id` é idêntico após +1 ano | "file_url is the blob redirect link…"; "blob signed_id is identical…" |
| `download_url` | `file.blob.url`: URL do serviço Disk, `/rails/active_storage/disk/<token>/<arquivo>`. Token válido por 5 min (`ActiveStorage.service_urls_expire_in`, activestorage 7.1.5.2, `lib/active_storage.rb:353`): 200 em +4m50s, 404 em +5m10s | "Disk URL answers 200 within 5 minutes and 404 afterwards" |
| Novo token | `download_url` muda a cada chamada com o relógio avançado; `file_url` não muda | "file_url does not change…, but download_url issues a new token" |
| `thumb_url` (imagem) | `/rails/active_storage/representations/redirect/<signed_id>/…`. Sem expiração; `find_signed` válido em +1 ano | "thumb_url is a representation route…" |
| Redirect em +1 ano | 302 para URL Disk nova; o conteúdo é servido | "blob redirect link does not expire…" |
| Proxy em +1 ano | 200 com o conteúdo, sem redirecionar | "blob proxy link does not expire…" |
| Assinatura adulterada | 404 em redirect, proxy, Disk e representação | "tampered signatures…"; "representation with a tampered signature…" |
| Callbacks das rotas ActiveStorage | exatamente: `Audited::Sweeper`, `Proc`, `authenticate_secure_password!`, `set_blob`, `set_representation`, `verify_authenticity_token`, `verify_same_origin_request`. Nenhum checa usuário nem conta | "exact list of before_action callbacks…" |
| Serviço do teste | Disk privado (`config/storage.yml`, grupo `test`, `config/environments/test.rb:38`) | "the test environment stores blobs in the private Disk service…" |

## 4. Leitura para a decisão (não é ACL)

- Quem tem o link (`file_url`, `thumb_url`, proxy ou redirect) recebe o conteúdo sem sessão, sem token de usuário e sem checagem de conta. O link não expira.
- A expiração de 5 min do Disk vale só para a URL direta. Como o redirect emite uma URL nova a cada acesso, o acesso efetivo pelo link é permanente.
- A assinatura impede adulteração (404), mas não limita quem recebeu o link válido.
- `download_url` está documentado no próprio código para serviços externos (`attachment.rb:61`). Um link entregue a um serviço externo tem o mesmo alcance.
- **Não alegar ACL pronta**: não há controle por usuário, conta ou epoch nesta base.

## 5. Limitações

- A medição vale só para o serviço Disk do ambiente de teste. Em dev e produção o serviço vem de `ACTIVE_STORAGE_SERVICE` (`config/environments/production.rb:43`, `development.rb:33`), e `config/storage.yml` tem S3, GCS, Azure e S3-compatível. URLs presignadas desses serviços não foram medidas e não estão provadas aqui. Não assumir `public_url`.
- Não há dados reais nem servidor Baileys real.

## 6. Proposta (não implementada; fase posterior, exige autorização humana)

1. Autorizar o acesso ao anexo pelo usuário autenticado e pela conta do anexo, no próprio app, em vez de confiar só no link.
2. Versionar o link com uma epoch por anexo ou por conta: trocar a epoch invalida os links já distribuídos.
3. Bloquear links diretos gerenciados (URL Disk ou presignada de serviço externo) como forma de acesso, e deixar `download_url` de fora de qualquer caminho de usuário final. Isso exige decidir como o serviço externo que usa `download_url` vai obter o arquivo.

Nada disso foi aplicado nesta tarefa.
