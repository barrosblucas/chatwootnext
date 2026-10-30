# 001 — Runner aceita só a lista fixa de extras G0 (connecta_g0_*)

## Contexto
O `--spec` do runner (`scripts/connecta/g0_test_env.sh`, função `db_state`) exige que as tabelas do `public` sejam exatamente as de `db/schema.rb`. O protótipo de escopo do T0.2 (parte A) precisa de 7 tabelas de teste no banco G0 (`connecta_g0_*`), criadas pelo helper `spec/connecta/support/g0_scope_schema.rb`, sem migração e sem alterar `db/schema.rb`. Sem mudança no runner, o `--spec` recusa o banco com `diverge: tabelas`. Evidência: `.context/evidence/g0/06-scope-policy-query.md` (seção 3) e o dry-run anterior à mudança.

## Decisão
O núcleo continua validado contra `db/schema.rb` como antes; as tabelas `connecta_g0_*` são aceitas somente se estiverem na lista fixa `G0_EXTRA_TABLES` (7 nomes). Qualquer outra tabela com esse prefixo faz o check falhar com `diverge: tabelas-g0`. Nenhum check de banco ou de posse foi desabilitado.

## Alternativas consideradas
- Criar as tabelas em outro schema do Postgres (`connecta_g0.*`): não exige mudar o runner, mas o nome final não é `connecta_g0_*` e o prefixo pedido no briefing deixa de valer.
- Desabilitar o check de tabelas no `--spec`: rejeitado; enfraquece a proteção contra banco divergente.
- Recarregar o schema versionado a cada execução: rejeitado; `db:schema:load` só é permitido em banco vazio.

## Consequências
- Quem criar uma tabela `connecta_g0_*` nova precisa adicioná-la a `G0_EXTRA_TABLES` no mesmo commit, senão o runner recusa o banco.
- Se o protótipo for descartado, remover as 7 tabelas exige autorização explícita (é ação destrutiva); a lista do runner fica então sem efeito.
- O check do núcleo não mudou, então um desvio em tabela do núcleo continua sendo detectado.

## Status
Aceita (spike G0, T0.2 parte A).

## Data
2026-10-22

## Atualização — 2026-10-23 (T0.7-s)

A lista `G0_EXTRA_TABLES` passa de 7 para 9 nomes: entram `connecta_g0_outbound_dispatches` e `connecta_g0_transfers`, criadas pelo helper `spec/connecta/support/g0_transfer_schema.rb` (spike de transferência e despacho, plano §8.2). A regra não muda: quem criar tabela `connecta_g0_*` nova adiciona o nome à lista no mesmo commit. A lista continua em ordem C.
