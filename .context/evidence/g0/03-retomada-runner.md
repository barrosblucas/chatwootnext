# G0 — retomada do runner (Fase 0, mesma autorização)

- Data (UTC): 2026-10-22, a partir de 15:43Z.
- Escopo: retomada da parte A da atribuição anterior, que expirou após 1500 s sem relatório. Anexos, AgentBot, T0.4/T0.5 e specs `spec/connecta/*` não foram tratados nesta retomada.
- Autorização: citação literal do briefing do orquestrador: "Pode seguirs uma vês que ese é um ambiente dev então é um ambiente seguro. Continue executando".
- Alvo: máquina local, worktree `chatwootnext-connecta-g0-prep`, projeto Compose `conecta-baileys-g0-test`, Postgres `127.0.0.1:55432`, Redis `127.0.0.1:56379`, banco `conecta_baileys_g0_test`, dados sintéticos.
- Estado do gate: **G0 continua ABERTO**. Esta retomada não prova EVID2..8, ACL nem transporte, e não aprova T0.2 a T0.7.

## 1. Processos da atribuição anterior

- Antes de qualquer ação, `ps` filtrado por `g0_test_env`, `rspec` e stub: nenhum processo ativo. Contêineres do projeto `healthy`: `conecta-baileys-g0-test-postgres-1` (ID `f0461ddc9f3e`) e `conecta-baileys-g0-test-redis-1` (ID `bf784eeeb8cb`).
- Último registro da atribuição anterior: 15:39Z, em `~/.cache/connecta-g0-test/logs/` (fora do repo). Não foi reexecutado nem apagado.
- Ao final, nenhum processo de runner, rspec ou stub restante (ver seção 8).

## 2. Baseline antes de qualquer edição

- `.context/evidence/g0/03-retomada-baseline-sha256.txt`: 18 arquivos. São os 16 do baseline `00` mais `04-runner-stub-tests.sh` e `04-runner-stub-tests.log`.
- `.context/evidence/g0/03-retomada-baseline-arquivos/`: cópias byte a byte dos mesmos 18 arquivos (`cmp` sem diferença).
- Divergência encontrada: `scripts/connecta/g0_test_env.sh` não batia com o baseline `00`/`03`.
  - Hash registrado (`00` e `03`): `89d790c7…`. Cópia dessa versão em `03-baseline-arquivos/`, com hash conferido.
  - Hash atual: `6007f841…`, mtime 15:20:36Z.
  - A evidência `01` afirma que o runner não mudou. Isso vale só até 15:02Z. A alteração foi feita pela atribuição anterior e não está documentada. Esta retomada não a reconstruiu: leu o código atual inteiro e o registrou no changelog.
- Demais divergências, já esperadas pela `01`: `PROJECT_STATE.md`, `REPOMAP.md`, `gotchas.md`, `CHANGELOG_2026_10_22.md`, `route_inventory_spec.rb` e `g0_target_guard.rb`.
- `04-runner-stub-tests.sh` (15:23:35Z) não estava no baseline `00`. Foi criado pela atribuição anterior.
- `spec/connecta/agent_bot_delivery_spec.rb` (15:37:56Z) e `spec/connecta/attachment_access_spec.rb` (15:37:00Z) têm mtime anterior ao início desta retomada. Não foram tocados.

## 3. Revisão do runner (sem edição nesta retomada)

Leitura integral de `scripts/connecta/g0_test_env.sh` (335 linhas). Critérios conferidos no código:

| Critério | Onde |
|---|---|
| Contexto Docker local antes de qualquer consulta ao daemon | `:108-111`, `:238-244` |
| Origem Compose inequívoca (rótulo de projeto e `config_files` no contêiner) | `:150-155`, `:158-164`, `:167-175` |
| Volume aceito só com rótulo do projeto e contêiner da origem; órfão recusado | `:126-132` |
| Porta livre, ou publicada por contêiner do projeto | `:112-122` |
| Segredo 0600; nunca regenerado com recursos do projeto | `:188-191`, `:291-298` |
| Schema carregado só em banco vazio; banco divergente aborta | `:305-321`, `:221-233` |
| Nenhum DROP, TRUNCATE, reset, prune ou remoção de volume; teardown sem `-v` | busca no arquivo: nenhuma ocorrência; `:331-332` |

Nenhuma edição foi necessária: o código atual atende aos critérios, e nenhuma validação abaixo reprovou o runner.

## 4. Validação (saídas reais)

Ruby da tarefa: `~/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin`, colocado na frente do PATH. Confirmado com `ruby -v` (3.4.4) e `bundle -v` (2.5.16).

| Comando | Exit | Resultado |
|---|---|---|
| `bash -n scripts/connecta/g0_test_env.sh` | 0 | sintaxe válida |
| `bash .context/evidence/g0/04-runner-stub-tests.sh` | 0 | `RESUMO: PASS=29 FAIL=0 SKIP=0` (`03-retomada-logs/stub-tests.log`) |
| dry-run com o Ruby da tarefa no PATH | 0 | todas as pré-condições `ok`; `banco conecta_baileys_g0_test com schema esperado (110 tabelas, 185 migrações); sem carga` (`03-retomada-logs/dry-run-prepare.log`) |
| dry-run sem o Ruby da tarefa no PATH (1ª tentativa; saída substituída pela 2ª) | 0 | 3 itens `falta`/`diverge`, causados por `mise ERROR No version is set for shim: ruby`. Erro de ambiente, não divergência real (ver `gotchas.md`) |
| `PATH=<ruby 3.4.4>:$PATH scripts/connecta/g0_test_env.sh --apply` (1ª repetição) | 0 | `up -d --wait`: contêineres `Running`/`Healthy`; `bundle install`: `378 gems now installed`; banco `sem carga` (`03-retomada-logs/apply-1.log`) |
| mesmo comando (2ª repetição) | 0 | idem (`03-retomada-logs/apply-2.log`) |
| `pg_dump --schema-only` duas vezes, sem filtro | — | hashes diferentes; 2 linhas `\restrict`/`\unrestrict` com token aleatório |
| mesmo dump, sem as linhas `\restrict`/`\unrestrict` | — | hashes iguais |
| `grep -lF -f <valor do segredo> 03-retomada-logs/*` | 1 | nenhum arquivo contém o valor do segredo (o valor não foi impresso) |
| `git diff --check` (rastreados) | 0 | sem saída |
| verificação direta de espaço no fim de linha e de newline final (não rastreados, 53 arquivos) | — | 0 problemas, após remover espaços em 3 logs gerados por esta retomada |

Não usei `git diff --no-index --check` para os não rastreados: ele retorna 1 para qualquer arquivo novo, sem relação com espaços.

## 5. Estado do banco e canário, antes e depois

Capturas em `03-retomada-logs/state-antes.txt`, `state-depois-1.txt` e `state-depois-2.txt`. As três são iguais (diff vazio, sem contar o cabeçalho com horário).

| Item | Valor |
|---|---|
| Canário (comentário do banco `conecta_baileys_g0_test`) | `g0-canario-sintetico-2026-10-22` |
| Migrações em `schema_migrations` | 185 |
| Tabelas em `public` | 112 (110 do `db/schema.rb` mais `schema_migrations` e `ar_internal_metadata`) |
| Views | 2 (112 tabelas + 2 views = 114 relações) |
| Extensões | `pg_stat_statements`, `pg_trgm`, `pgcrypto`, `plpgsql`, `unaccent`, `vector` |
| `ar_internal_metadata.schema_sha1` | `d72f597…`, igual ao SHA1 de `db/schema.rb` (pré-condição `match`) |
| Hash do schema (`pg_dump --schema-only`, sem linhas `\restrict`) | `80ced235…`, igual nas três capturas |
| Contêineres | postgres `f0461ddc9f3e`, redis `bf784eeeb8cb`; sem recriação |
| Rede | `fdc1efdf74dd` |
| Volume `conecta-baileys-g0-test_g0_postgres` | criado em `2026-10-22T14:45:09Z`, inalterado |
| Segredo sintético | mesmo inode, mesmo mtime, modo 600, 64 bytes; conteúdo não lido |

## 6. Negativos (AC2)

Os negativos foram provados com o stub, que substitui `docker` e `bundle` no PATH e isola `HOME` em diretório temporário. Ele não toca o daemon nem o segredo real. Casos da `04-runner-stub-tests.sh` (29 PASS):

- Contexto Docker remoto: aborta antes de consultar o daemon (caso 6).
- Recursos de outra origem: volume órfão, volume de outro projeto e contêiner de outro worktree são recusados (caso 4).
- Segredo ausente com recursos do projeto, e segredo com permissão 644: abortam sem regenerar (caso 5).
- `.env` na raiz, e alvo de banco apontando para outra porta: abortam antes de qualquer comando (caso 8).
- Porta ocupada sem dono do projeto: aborta (caso 7). Banco divergente, ou Postgres sem resposta: aborta sem carga (caso 3).
- Reutilização de recursos próprios e carga única em banco vazio (casos 1 e 2). Specs fora da allowlist (caso 9) e specs no alvo G0 (caso 10).

Os negativos não foram repetidos contra o ambiente real: isso exigiria trocar o contexto Docker ou mover o segredo real.

## 7. Limitações e pendências

- **Teardown seguido de preparo**: `--teardown --apply` deixa o volume sem contêiner, e o `--apply` seguinte recusa esse volume (caso 4 do stub; `scripts/connecta/g0_test_env.sh:126-132`). Decisão pendente registrada em `PROJECT_STATE.md`, item 10. Não testado no ambiente real, porque o teardown derrubaria os serviços do G0.
- O cabeçalho de `04-runner-stub-tests.sh` (linha 6) cita `05-execucao-repetivel.md`, que não existe. Esta evidência é a prova real. O arquivo pertence à atribuição anterior e não foi editado.
- Specs não foram executadas nesta retomada: fora do escopo (anexos e AgentBot). A última execução do T0.1 está em `01` e `02`.
- Sem `shellcheck`: não instalado, não executado.
- Os diretórios `.context/`, `scripts/` e `spec/*/connecta/` seguem não rastreados. Nada foi commitado, nem feito push, merge, rebase ou PR.

## 8. Estado final

- Processos: ao final, `ps` filtrado por `g0_test_env`, `rspec` e `g0-stub` não encontrou nenhum processo ativo (ver resultado da verificação em seguida).
- `sha256sum -c 03-retomada-baseline-sha256.txt`: OK em 14 arquivos (runner, compose, `route_inventory_spec.rb`, `g0_target_guard.rb`, `04-runner-stub-tests.sh` e `.log`). Diferem do baseline apenas os 4 documentos editados nesta retomada: `PROJECT_STATE.md`, `REPOMAP.md`, `gotchas.md` e `CHANGELOG_2026_10_22.md`.
- `git status --porcelain -uno`: vazio. Nenhum arquivo rastreado foi alterado.

## 9. Arquivos

- Criados: este arquivo; `03-retomada-baseline-sha256.txt`; `03-retomada-baseline-arquivos/` (18 cópias); `03-retomada-logs/` (`stub-tests.log`, `dry-run-prepare.log`, `apply-1.log`, `apply-2.log`, `state-antes.txt`, `state-depois-1.txt`, `state-depois-2.txt`).
- Atualizados: `PROJECT_STATE.md` (entrega, decisões 7 e 10), `gotchas.md` (runner reexecutável superado; três armadilhas novas), `REPOMAP.md` (pasta `evidence/g0/`), `changelog/CHANGELOG_2026_10_22.md` (seção da retomada).
- Não alterados: `scripts/connecta/g0_test_env.sh`, `scripts/connecta/g0-test-services.compose.yml`, `spec/connecta/*`, `spec/requests/connecta/route_inventory_spec.rb`, `spec/support/connecta/g0_target_guard.rb`, `04-runner-stub-tests.*`, todos os arquivos rastreados.

G0 segue **ABERTO**.
