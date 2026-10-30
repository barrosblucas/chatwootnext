# Evidência 21 · T0.7c-2 instabilidade da transferência (hipótese, achado e limpeza escrita — SEM prova nova)

Data: 2026-10-24. Worktree: `/home/thanos/chatwootnext-connecta-g0-prep`, branch `feat/connecta-g0-prep`.
TASK_ID: g0-t07c2 (turno documental: SOMENTE documentação; nenhum código/spec novo, nenhuma execução).

**Estado: DOCUMENTAÇÃO (NÃO VALIDADO).** Nenhum spec foi executado neste turno. Não há run novo,
log novo de spec, RuboCop executado, nem validação funcional. Este arquivo consolida o que já estava
escrito/registrado em turnos anteriores e declara explicitamente o que continua pendente.

## 1. Hipótese (NÃO provada): concorrência sem fila

- Hipótese de trabalho registrada nos turnos anteriores: a instabilidade observada na transferência
  decorreria de concorrência sem fila — mensagens entrando em threads ao mesmo tempo que a transação
  de transferência (`Connecta::Transfer::LocalTransaction`), sem um mecanismo de fila entre elas.
- Status da hipótese: **hipótese, não conclusão**. Nenhuma nova execução ocorreu neste turno para
  confirmar, refutar ou medir essa causa. Não declarar correção de instabilidade provada.
- O que a hipótese orientou no código já escrito (sem alegar prova): `transfer_cutover_spec.rb`
  modela a corrida com threads reais (mensagens em threads + transferência no meio da rajada) e a
  serialização esperada é a do Postgres (`IncomingHook` e `LocalTransaction`), com o lock de contato
  em Redis fora da prova (stubado) por inanição entre threads — ver seção 4.

## 2. Achado concreto: `transfers` e `dispatches` SEM `account_id`

- Achado verificado em fonte estável, sem execução nova:
  `spec/connecta/support/g0_transfer_schema.rb` cria `connecta_g0_transfers` e
  `connecta_g0_outbound_dispatches` **sem coluna `account_id`**.
  - `transfers`: chaves de conversa `source_conversation_id` / `destination_conversation_id`
    (índice parcial único de pedido aberto por conversa de origem).
  - `dispatches`: chave de conversa `conversation_id` (+ `message_id` único).
- Consequência para a limpeza (já refletida no código escrito, sem alegar execução): a limpeza da
  spec de corte NÃO pode filtrar essas tabelas por conta. O `after` de `transfer_cutover_spec.rb`
  remove de `TransferRecord`/`OutboundDispatchRecord` **só as linhas das conversas da inbox do
  próprio exemplo** (`Conversation.where(inbox: whatsapp_inbox).pluck(:id)`), ANTES de apagar as
  conversas, e conta sobras novas (`transfers_by_conversation`, `dispatches_by_conversation`) com
  expectativa de zero. Tabelas COM `account_id` continuam limpas por conta (`account.id`).

## 3. Logs antigos de 0 exemplos NÃO provam estabilidade

- `.context/evidence/g0/21-logs/serial-summary.tsv` registra 2 runs (`policy-alone-1`, `policy-alone-2`)
  com `exit 0`, `examples 0`, `failures 0`.
- Leitura correta: **0 exemplos executados ⇒ 0 falhas possíveis ⇒ nenhuma evidência de estabilidade**.
  Esses logs são pré-condição/ambiente (spec `scope_policy_query_spec.rb` no alvo G0), não prova de
  transferência, despacho, corte temporal ou integração.
- `policy-alone-5.log` tem 0 bytes (vazio): também não prova nada.
- Os 39 exemplos / 0 falhas no tail de `policy-plus-cutover-1.log` são de execução antiga
  (`scope_policy_query_spec.rb` + `transfer_cutover_spec.rb`), anteriores à escrita da integração
  T0.7c-2 e à conclusão do ensure/rollback/join. Não são reaproveitados como prova do estado atual:
  **nenhuma nova execução ocorreu**.

## 4. Limpeza futura por IDs das fixtures (escrita, NÃO executada)

- `spec/connecta/transfer_cutover_spec.rb` (estado após o turno de código COMPLETED de 2026-10-24):
  - `after`: limpa por IDs próprios — dispatches/transfers pelas conversas da inbox do exemplo,
    escopos/contact_inboxes pela inbox do exemplo, org_units pelo prefixo do `run_id`, tabelas com
    `account_id` pela conta do exemplo; depois conta sobras e espera zero em todas.
  - Concorrência: os 2 trechos com threads (`[transfer].compact + workers` e `message_thread`)
    têm `ensure` com `join` limitado (10 s), `kill` se ainda viva, e `release_connection`; erros de
    thread são propagados via `value` (o `join` sozinho não relança). `ruby -c` passou no turno de
    código (via PATH explícito do toolchain). **Specs NÃO executadas** por ordem do humano.
- `spec/connecta/transfer_integration_spec.rb` (11 exemplos escritos, NÃO EXECUTADOS — ver evidência 18):
  usa o fixture de escopo **transacional** (`include_context 'with connecta g0 scope fixture'`):
  o rollback limpa tudo, **sem `after` manual**. O "despacho em voo" é simulado (linha gravada como
  `dispatching` antes do `begin!`); transporte stubado (`SendOnWhatsappService` dobrado, `SendReplyJob`
  real); sem sleep, sem rede, sem threads.
- Resíduos antigos **preservados, sem DELETE manual**: o inventário antigo
  (`21-logs/db-inventory-before.log`, 2026-10-23) listava **87 linhas em `connecta_g0_transfers`**
  (relato do turno anterior fala em ~111 em outro instante) com `inbox_id`/`conversation_id` NULL na
  extração JSON — ou seja, linhas órfãs/legado sem vínculo localizável por conta ou conversa. A
  limpeza escrita remove **somente** linhas das conversas do próprio exemplo; resíduos de outras
  execuções ficam intactos por desenho (nenhum `DELETE` manual fora da spec, nenhum teardown, nenhum
  SQL manual executado neste turno).

## 5. Correção escrita vs. prova pendente (separação explícita)

| Item | Status |
|---|---|
| Hipótese concorrência-sem-fila | Hipótese, NÃO provada; nenhuma nova execução |
| Achado `transfers`/`dispatches` sem `account_id` | Achado concreto em fonte estável (`g0_transfer_schema.rb`) |
| Logs antigos de 0 exemplos | NÃO provam estabilidade (0 exemplos ⇒ 0 falhas possíveis) |
| Resíduos antigos (87/~111 linhas órfãs) | Preservados; sem DELETE manual; limpeza futura só por IDs do exemplo |
| `transfer_cutover_spec.rb` ensure/rollback/join + limpeza por IDs | Escrito e concluído no turno de código; `ruby -c` passou; **spec NÃO executada** |
| `transfer_integration_spec.rb` 11 exemplos | Escrita conforme log; **NÃO EXECUTADA**; limpeza via rollback transacional |
| Prova funcional (specs T0.7 + RuboCop + regressões) | **Pendente**, tarefa posterior por ordem do humano |

## 6. Arquivos e validação deste turno documental

- Criado: este arquivo (`.context/evidence/g0/21-instabilidade.md`).
- Append: `.context/evidence/g0/18-t07c-integracao.md` (seção 5: specs escritos, não executados) e
  `.context/changelog/CHANGELOG_2026_10_24.md` (entrada T0.7c-2 documental).
- Lido (só fontes estáveis necessárias): `g0_transfer_schema.rb` (achado sem `account_id`),
  contagem/lista dos 11 `it` de `transfer_integration_spec.rb`, `ensure`/`join`/limpeza de
  `transfer_cutover_spec.rb`, `21-logs/serial-summary.tsv` + `policy-alone-1.log` (0 exemplos),
  `21-logs/db-inventory-before.log` (resíduos), logs de turno g0-t07c2 (atual COMPLETED só código;
  anterior BLOCKED com spec escrita sem docs), evidência 18, changelog do dia.
- NÃO tocados: código/specs, `scope/**`, installer, runner, schema, core, `.env`, banco, servidor,
  produção, `PROJECT_STATE.md`, plano, outros documentos.
- Validação: `df -h /tmp` antes (sem apagar); `git diff --check`; `git status --short`; verificação
  de existência dos links citados. **Sem testes, sem lint, sem build, sem execução de specs.**
