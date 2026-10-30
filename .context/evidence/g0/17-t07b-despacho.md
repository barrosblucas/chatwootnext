# Evidência 17 · T0.7b despacho de saída com barreira de transferência (spike G0)

Data: 2026-10-23. Worktree: `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`. Dados sintéticos, banco `conecta_baileys_g0_test`, execução só pelo runner `scripts/connecta/g0_test_env.sh --spec --apply` sob `spec.lock`. Sem rede: o conector é stubado na fronteira `Whatsapp::SendOnWhatsappService`.

**Estado: FECHADO (T0.7b), AC1 a AC5 verdes.** Resultado final: `outbound_dispatch_spec.rb` + `transfer_cutover_spec.rb` = **19 exemplos, 0 falhas, exit 0** (`run-8-pair-final-409.log`). RuboCop nos 4 arquivos tocados: sem ofensas (`rubocop-t07b-final.log`). Nada rastreado foi alterado.

## 1. O que foi construído

- `app/services/connecta/transfer/outbound_dispatch.rb`: `Connecta::Transfer::OutboundDispatch` (métodos de classe) e `OutboundDispatch::MessageHook`.
  - `dispatchable?(message)`: saída (`outgoing` ou `template`), não privada, sem `source_id`, de inbox presente em `connecta_g0_scoped_inboxes`. Espelha os filtros de `Base::SendOnChannelService#invalid_message?`.
  - `enqueue!(message)`: `insert_all` com `ON CONFLICT DO NOTHING` (idempotente) da linha `queued`.
  - `claim!(message)`: uma instrução SQL (`CLAIM_SQL`): troca `queued` por `dispatching` se existe escopo `active` da conversa, senão `parked`; `RETURNING state`. Verdadeiro só para quem trocou para `dispatching`.
  - `resolve!(message, state)`: grava `accepted`/`failed`/`uncertain` e o `source_id` do conector em `connector_message_id`.
  - `prepare_transfer!(conversation)`: devolve `Result(parked, wait)`; levanta `OutboundDispatch::ConflictError` com `uncertain`.
  - `MessageHook#send_reply` (privado): chama `enqueue!` antes do `super` (o `after_create_commit` de `Message`).
- `app/services/connecta/transfer/send_reply_hook.rb`: `Connecta::Transfer::SendReplyHook#perform`, prepend em `SendReplyJob`. Inbox não marcada ⇒ `super`. Marcada ⇒ `enqueue!`, `claim!`, e só o vencedor chama `super`.
- `app/services/connecta/transfer/installer.rb`: `install!` passa a prepend `MessageHook` em `Message` e `SendReplyHook` em `SendReplyJob`, além do `IncomingHook` de T0.3 (que continua igual). Só em `Rails.env.test?`.
- `spec/connecta/outbound_dispatch_spec.rb`: 10 exemplos. 9 com o fixture de escopo (transacional) e 1 concorrente sem transação externa, no padrão do T0.3.

## 2. Decisões (com motivo)

- **Onde nasce `queued`:** na criação da mensagem (`Message#send_reply`), não só dentro do job. Se a linha nascesse só no job, `prepare_transfer!` nunca encontraria envio pendente para parkear, e o passo 3 do plano (`queued` ⇒ `parked` no início da transferência) ficaria vazio. O job também chama `enqueue!` antes do claim, porque `SendReplyJob` é enfileirado direto em outros caminhos (retry e reações do controller). A inserção é idempotente.
- **Claim em uma instrução:** a troca de estado e a checagem de `active` são uma única SQL. Com dois passos (tentar `dispatching`; se falhar, marcar `parked`), uma transferência abortada entre os passos (volta a `active`) deixaria a mensagem `parked` sem motivo.
- **`prepare_transfer!`:** roda em `transaction(requires_new: true)`. Com `uncertain`, o `park` feito antes é desfeito: a transferência fica retida sem efeito colateral. Ordem: parka `queued` primeiro, depois lê `dispatching`/`uncertain` numa só consulta. Um claim em andamento segura a linha até o commit, e o `UPDATE` do park espera por ele; a leitura posterior o enxerga.
- **`uncertain` tem precedência sobre `wait`:** com os dois presentes, o conflito (409) vence, porque a transferência já não pode prosseguir.
- **Ambíguo ⇒ `uncertain`:** `Timeout::Error` (inclui `Net::ReadTimeout` e `Net::OpenTimeout`; verificado no Ruby 3.4.4 do toolchain) e `MessageAlreadyProcessingError` (409 do provedor, envio ainda em processamento). Outro erro ⇒ `failed`. Retorno normal com `message.failed?` (ex.: janela de mensagem fora de alcance, que o serviço grava sem exceção) ⇒ `failed`.
- **Re-lança após gravar:** o job continua falhando visivelmente. Reenvio é impedido pelo claim (só age sobre `queued`), não pelo job não ser reenfileirado.
- **`resolved_at`/`resolved_by` não são tocados:** são da conciliação do operador (plano §6.5 item 4).

## 3. Resultados (runs reais, em `17-logs/`)

| Run | Conteúdo | Resultado | Exit | Situação |
|---|---|---|---|---|
| run-1-outbound | primeira execução do spec | 9 ex., 1 falha: FK na limpeza (ver 5) | 1 | superado |
| run-2-outbound | após correção da limpeza | 9 ex., 0 falhas | 0 | superado (antes dos ajustes de RuboCop e da reestruturação) |
| run-3-pair | outbound + cutover | 18 ex., 0 falhas | 0 | superado |
| run-4-mutacao-sem-escopo | controle negativo (ver 4) | 9 ex., 1 falha (`spec:36`) | 1 | restaurado |
| run-5-pair-final | código final, antes do 409 | 18 ex., 0 falhas | 0 | superado |
| run-6-mutacao-sem-where-queued | controle negativo (ver 4) | 9 ex., 4 falhas (`spec:27,77,88,170`) | 1 | restaurado |
| run-7-pair-final-restaurado | antes do 409 | 18 ex., 0 falhas | 0 | superado |
| run-8-pair-final-409 | **final** | **19 ex., 0 falhas** | 0 | **válido** |

RuboCop: `rubocop-t07b.log` (7 ofensas, antes dos ajustes), `rubocop-t07b-fechamento.log` (sem ofensas, após ajustes), `rubocop-t07b-final.log` (sem ofensas, código final, `env -i` com as variáveis `BUNDLE_*` do launcher).

Observação sobre as mutações: as runs 4 e 6 foram feitas antes da reescrita final de `outbound_dispatch.rb`. Nessa reescrita o `CLAIM_SQL` ficou idêntico ao testado (conferido por `grep` depois de cada restauração).

## 4. Controles negativos

| Controle | Mudança | Resultado |
|---|---|---|
| AC2, escopo | `ELSE 'dispatching'` no `CASE` (sem checar `active`) | run-4: falha no late worker (`outbound_dispatch_spec.rb:36`). Restaurado |
| AC4, atomicidade | `WHERE` sem `d.state = 'queued'` | run-6: 4 falhas, incluindo a corrida (`spec:170`). Restaurado |

## 5. Problemas encontrados e corrigidos

- Run 1: a limpeza por tabela falhou com `ForeignKeyViolation` em `internal_chat_channels`. Causa: `Account` cria chat interno no `after_create_commit` (`app/models/account.rb:121`), e a ordem da lista de tabelas não respeita a FK. Correção: `session_replication_role = replica` só durante a limpeza sintética, restaurado no `ensure`. A checagem de sobras por conta continua valendo.
- A mensagem de saída da fábrica cria um usuário remetente. A tabela `users` não tem `account_id`, então a limpeza e a checagem de sobras não a alcançariam. Correção: o remetente do exemplo concorrente é o contato.
- Sobras do run 1 (conta criada às 17:43:06, mesmo horário do log): removidas com `DELETE` por id, em uma transação (`psql -1 -v ON_ERROR_STOP=1`), depois de leitura prévia: 1 mensagem (`messages.id 4089`), 1 conversa, 1 canal de chat interno (`internal_chat_channels.id 2501`) e seus membros, 1 usuário (`users.id 9371`, criado na mesma janela, sem `account_users`), e a conta (`accounts.id 2495`). Verificado: 0 contas, 0 linhas de despacho depois de cada run.
- RuboCop: `Rails/SkipsModelValidations` nos dois `insert_all`/`update_all` (justificados: idempotência e condição de estado); comprimento da linha do `installer.rb`; `RSpec/MultipleDescribes` desligado na linha do describe concorrente (precisa de `use_transactional_tests = false`, incompatível com o fixture); `RSpec/LetSetup` (setup sem referência movido para `before`); linha em branco após `let!`.

## 6. Limites e decisões que o revisor deve conhecer

- **Prova de corrida:** o exemplo concorrente força sobreposição com `sleep 0.2` no conector. A garantia vem do `UPDATE` condicional (run-6 mostra que o exemplo pega a remoção da condição). Não é um detector probabilístico: uma execução, sem repetições.
- **Ligação à transferência:** `prepare_transfer!` não está ligado a `LocalTransaction.begin!`. Essa integração é tarefa posterior (fora de escopo, T0.7a). Hoje o hook só roda quando o spec chama `install!`.
- **Reenvio manual não é coberto:** `messages_controller#retry` e as reações enfileiram `SendReplyJob` direto. Em inbox marcada, a linha da mensagem já existe (`accepted`/`failed`), o claim recusa e não há reenvio. É o comportamento do plano ("`failed` ⇒ sem reenvio automático"), mas um reenvio manual intencional precisaria de nova linha, e o índice único em `message_id` impede. Decisão pendente.
- **Timeout e 409 reais:** a classificação foi conferida por leitura de código (`whatsapp_baileys_service.rb:132` e `:706`, sem wrapper que troque a classe). Não houve chamada a um provedor real (sem rede, por regra do G0).
- **Visibilidade de `parked`:** o status "não enviada: chamado transferido" é UI (Fase 5). Aqui só a linha muda.
- **Mensagem já entregue ao cidadão** não pode ser recolhida (limite do plano, item 5).

## 7. Arquivos e alterações no repo

- Novos: `app/services/connecta/transfer/outbound_dispatch.rb`, `app/services/connecta/transfer/send_reply_hook.rb`, `spec/connecta/outbound_dispatch_spec.rb`, este arquivo e os logs em `.context/evidence/g0/17-logs/`.
- Alterado: `app/services/connecta/transfer/installer.rb` (dois `prepend` e comentário).
- Atualizado: `.context/changelog/CHANGELOG_2026_10_23.md` (entrada T0.7b, por append).
- Não tocados: `local_transaction.rb`, `spec/connecta/transfer_activation_spec.rb`, `transfer_record.rb`, `outbound_dispatch_record.rb`, `spec/connecta/support/*`, `scripts/connecta/*`, `app/services/connecta/scope/**`, arquivos do core, `.context/PROJECT_STATE.md`. Nenhum arquivo rastreado alterado.

## 8. Candidatos a `gotchas.md` (não gravados aqui: fora do escopo desta tarefa)

- `2026-10-23 — Account cria chat interno em after_create_commit (app/models/account.rb:121) com FK para canais e membros; a limpeza sem transação que apaga tabela por tabela falha conforme a ordem. Usar session_replication_role = replica só na limpeza — evidência: 17-logs/run-1-outbound.log`
- `2026-10-23 — a fábrica de mensagem cria usuário remetente quando não recebe sender; users não tem account_id, então escapa da checagem de sobras por conta. Passar sender de contato — evidência: spec/connecta/outbound_dispatch_spec.rb (contexto concorrente)`
