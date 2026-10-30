# Evidência 10 · T0.3 corte temporal (spike G0)

Data: 2026-10-23. Worktree: `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`. Dados sintéticos, banco `conecta_baileys_g0_test`, execução só pelo runner `scripts/connecta/g0_test_env.sh --spec --apply`.

**Estado final: FECHADO (T0.3).** A validação que ficou pendente após o bloqueio de disco foi executada em 2026-10-23: spec 9 exemplos, 0 falhas; spec + `scope_policy_query_spec.rb` 39 exemplos, 0 falhas; RuboCop sem ofensas; nada rastreado alterado. Resultados na seção 7. Os limites da seção 6 continuam valendo.

## 1. O que foi construído

- `app/services/connecta/transfer/local_transaction.rb`: `Connecta::Transfer::LocalTransaction`.
  - `lock!(inbox_id:, contact_id:)`: `SELECT pg_advisory_xact_lock(hashtextextended('connecta:transfer:<inbox>:<contato>', 0))`.
  - `call`: numa transação, reabre a origem com `find_by!(id:, state: 'active')` sob o lock, faz `active → transferring → transferred_out`, cria a conversa de destino (mesmo `account`, `inbox`, `contact` e `contact_inbox` da origem) e grava o escopo de destino `pending_activation`, `case_protocol` igual, `case_version: 0`.
- `app/services/connecta/transfer/incoming_hook.rb`: `Connecta::Transfer::IncomingHook` (prepend em `Whatsapp::IncomingMessageBaileysService`).
  - `set_conversation`: pega o mesmo lock de (inbox, contato), busca o escopo não terminal do par (`NON_TERMINAL_STATES`) e usa a conversa dele; sem escopo, cai no `super` nativo.
  - `handle_individual_contact_message`: envolve o handler inteiro em `ActiveRecord::Base.transaction { super }`.
- `app/services/connecta/transfer/installer.rb`: `Connecta::Transfer::Installer.install!`, só em `Rails.env.test?`, chamado só pela spec.
- `spec/connecta/transfer_cutover_spec.rb`: 9 exemplos.

## 2. Desenho do lock e um desvio do briefing

**Lock.** Um único bigint por `(inbox_id, contact_id)` via `hashtextextended`, para não estourar int4 nos dois argumentos de `pg_advisory_xact_lock(int, int)`. É lock de transação: solta no commit ou rollback.

**Por que o hook envolve o handler inteiro (desvio).** O briefing pede o hook em `set_conversation`. O fluxo Baileys de contato individual não permite isso: `app/services/whatsapp/baileys_handlers/concerns/individual_contact_message_handler.rb:37-39` chama `set_conversation` e depois `handle_create_message`, sem transação própria. Um lock tomado só dentro de `set_conversation` é solto antes do INSERT da mensagem. Sem transação envolvendo o handler, uma transferência podia commitar entre a resolução da origem e a gravação, e a mensagem entrava numa origem já `transferred_out`. O controle negativo A (seção 4) mostra que a transação é necessária.

**Ordem dentro da transferência.** O índice único parcial de `connecta_g0_conversation_scopes` conta `transferring` como não terminal. Por isso a origem vai a `transferred_out` antes do INSERT do destino. Estados intermediários: `active → transferring → transferred_out`, tudo na mesma transação.

## 3. Resultados (runs reais)

Arquivos de log em `.context/evidence/g0/10-logs/`.

| Run | Versão | Resultado |
|---|---|---|
| run-10 `run-10-real-com-determinista.log` | implementação real, 9 exemplos | **9 exemplos, 0 falhas** |
| run-13 `run-13-final-transfer.log` | spec antes da reescrita final | **9 exemplos, 0 falhas**, 48,96 s |
| run-14 `run-14-final-com-regressao-scope.log` | spec + `scope_policy_query_spec.rb` | **39 exemplos, 0 falhas** (9 + 30), 2 min 3 s |

Contagens da corrida (run-10, 5 repetições, 20 mensagens concorrentes + 1 semente por repetição, 3 threads de mensagem e 1 de transferência, a transferência entra após 5 mensagens commitadas). Cada repetição: 21 linhas em `messages`, nenhuma perdida nem duplicada.

| Repetição | Origem | Destino | Commitadas antes da transferência | Iniciadas após | Em voo no corte |
|---|---|---|---|---|---|
| 1 a 5 | 8 | 13 | 6 | 10 | 5 |

No run-8 (mesma implementação, antes do exemplo determinístico) a origem ficou entre 8 e 9 e o destino entre 12 e 13 nas 5 repetições.

Limite do oráculo da corrida: o critério "antes do commit" usa timestamps monotônicos de início e fim de cada `perform`. Mensagens em voo no corte não têm classificação temporal. Nelas a verificação é só a consistência de ids: toda mensagem da origem tem id menor que toda do destino.

## 4. Controles negativos

Feitos de propósito e restaurados depois de cada um.

| Controle | Mudança | Resultado |
|---|---|---|
| A (primeira versão da spec, só corrida) | sem `ActiveRecord::Base.transaction` em `handle_individual_contact_message` (`run-9`) | **5 repetições passaram**: a corrida não detecta a falta da transação, porque a janela entre resolver a origem e gravar a mensagem é de milissegundos |
| A (com exemplo determinístico) | igual (`run-11`) | **1 falha**: `expected: nil, got: true`, a transferência commitou com a mensagem em voo |
| B (sem lock do Postgres) | `lock!` vira `return` (`run-12`) | **1 falha** no mesmo exemplo determinístico (`expected: nil, got: true`); as repetições da corrida passaram |

Conclusão: a corrida sozinha tem pouco poder de detecção. O exemplo determinístico ("mensagem já resolvida na origem e ainda em voo", `transfer_cutover_spec.rb`) é o que prova a janela: uma mensagem pausada depois da resolução na origem faz a transferência esperar até o commit dela. Ele falha com A e com B e passa com a implementação real.

## 5. Problemas encontrados e corrigidos (com logs)

- Run 1 (`run-1-transfer.log`): 8 falhas. Causa: o aviso de recebimento ao baileys-api (`Channel::Whatsapp#received_messages`, HTTP bloqueado pelo WebMock) rodava porque o canal foi criado com `build`, que não passa pela fábrica (o stub do aviso fica no `before(:create)`).
- Run 2 (`run-2-transfer.log`): `ArgumentError: wrong number of arguments (given 1, expected 0)` no `allow`. Causa: um `let(:receive)` local sombreava o matcher `receive` do RSpec. Renomeado para `deliver`.
- Run 3 (`run-3-transfer.log`): 8 exemplos verdes após `create(:channel_whatsapp, ..., validate_provider_config: false, received_messages: false)`, o mesmo padrão do spec de Baileys (a fábrica da inbox chama `channel.save!`, que faz `GET /status/auth`).
- Run 5 (`run-5-mutacao-sem-transacao.log`): com a transação removida apareceu `Timeout::Error: Timeout acquiring contact lock` numa repetição. Causa: inanição do lock de contato em Redis (MockRedis): o polling de 0,1 s perde a corrida contra a thread que acabou de soltar o lock. Esse lock fica fora da prova (ver seção 6).

## 6. Limites e decisões que o revisor deve conhecer

- **Lock de contato em Redis passado direto no spec** (`allow_any_instance_of(...).to receive(:with_contact_lock)`, com RuboCop inline `RSpec/AnyInstance`, como o resto do repo). A serialização entre mensagens do mesmo contato passa a ser só a do Postgres, que é o que a prova deve medir. Em produção o lock de Redis continua ativo.
- **Só o caminho Baileys de contato individual** (`handle_individual_contact_message`) recebe o hook. Os caminhos de grupo, cloud e Z-API não foram tocados.
- **A origem não é resolvida.** A transferência não muda `status` da conversa de origem (o plano prevê `resolved`). Isso fica para o T0.7, junto da ativação e do outbox.
- **Par sem escopo não terminal cai no caminho nativo.** Depois de uma transferência o par sempre tem escopo `pending_activation`, então a janela não aparece na spec. Não está coberto um par só com `transferred_out`.
- **Destino nasce com `case_version: 0`**, porque a versão só vem da plataforma na ativação (T0.7).
- **Limpeza.** O `after` apaga, por `account_id`, em toda tabela com essa coluna (lista lida do banco), e por `inbox_id` nos escopos e `contact_inboxes`, e por caminho nas unidades organizacionais. Não há FK relevante entre essas linhas. Desde o fechamento, o `after` confere por consulta que nada sobrou (contagem por conta em todas as tabelas com `account_id`, por prefixo `/t03-<run_id>/` nas unidades e por `inbox_id` nos escopos e `contact_inboxes`), e os dados são únicos por execução (`run_id` e `run_digits`). A checagem não foi testada com uma sobra induzida: passar com zero mostra o estado, não que ela acusaria uma sobra.
- **Hash do lock**: `hashtextextended` é de 64 bits. Colisão com outro uso de advisory lock no mesmo banco é teoricamente possível e não é tratada.
- **Ordem de limpeza do Redis de processamento**: `clear_message_source_id_from_redis` roda antes do commit do wrapper. Entre um e outro há uma janela para duplicata por webhook repetido. Não está coberta.

## 7. Validação pendente (executada depois do bloqueio de disco)

Depois do run-14 e da última reescrita da spec, o volume `/tmp` (usado pelo harness do Claude Code) ficou sem cota. Todo comando de shell falhou com `EDQUOT`, inclusive o sandbox do context-mode (`Unknown system error -122`). Não apaguei nada em `/tmp`, porque é diretório do harness e a orientação é pedir antes.

Executada em 2026-10-23, com o disco liberado (`/tmp` com 2,3 GB livres no início). Todas as specs pelo runner, sob o lock `spec.lock`. Logs em `.context/evidence/g0/10-logs/`.

1. `scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/transfer_cutover_spec.rb`: **9 exemplos, 0 falhas, exit 0** (`run-17-transfer-final.log`).
2. Mesmo runner com `spec/connecta/scope_policy_query_spec.rb`: **39 exemplos, 0 falhas, exit 0** (`run-18-transfer-mais-scope-policy-final.log`).
3. RuboCop com `env -i` e as variáveis `BUNDLE_*` do launcher, em `app/services/connecta/transfer/*.rb spec/connecta/transfer_cutover_spec.rb`: **4 arquivos, sem ofensas, exit 0** (`rubocop-t03-fechamento.log`). A primeira rodada desta validação deu 5 ofensas: uma linha de 156 caracteres e `RSpec/ExpectInHook` nas checagens do `after`. Corrigidas com os JIDs em `let` e a checagem de sobras num único `expect`, com `rubocop:disable RSpec/ExpectInHook` na linha. Os runs 15 e 16 (`run-15-transfer-unico.log`, `run-16-transfer-mais-scope-policy.log`) são da versão anterior a esse ajuste: 9 e 39 exemplos, 0 falhas.
4. `git status --short`: só linhas `??`, nenhuma alteração rastreada (`git diff --name-only` e `git diff --cached --name-only` vazios). `git diff --check`: sem saída. O spec não rastreado foi conferido com `git diff --no-index --check /dev/null`, sem saída; sem espaço no fim de linha nem tabs.

Ajustes desta rodada (AC1, dados únicos por execução): `run_id` (hex de 4 bytes) nas paths das unidades (`/t03-<run_id>/a/`, `/b/`) e no nome da inbox; `run_digits` (8 dígitos) no LID e no telefone. As mensagens `msg-N` não receberam prefixo: `find_message_by_source_id` busca em `inbox.messages`, e a inbox já é única por execução. A limpeza das unidades usa o prefixo, e o `after` termina com a checagem de sobras. Ela esteve vazia nas 9 execuções, porque o `expect` passou.

## 8. Arquivos e alterações no repo

- Novos: `app/services/connecta/transfer/{local_transaction,incoming_hook,installer}.rb`, `spec/connecta/transfer_cutover_spec.rb`, este arquivo e os logs em `.context/evidence/g0/10-logs/` (run-1 a run-18, `rubocop-t03.log` e `rubocop-t03-fechamento.log`).
- Não tocados por mim: `app/services/connecta/scope/**`, `spec/connecta/support/*`, `scripts/connecta/*`, `conversation_http_hook.rb`, arquivos do core, `db/schema.rb`, migrations, `.context/PROJECT_STATE.md`. Não editei nenhum arquivo rastreado: `git status --short` mostra só não rastreados (seção 7).
