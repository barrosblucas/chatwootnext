# 35 — Dossiê Gate G0 (factual, pré-Juiz T2) — status READY_FOR_T2 (NÃO APPROVED)

- Data (UTC): 2026-10-24.
- TASK_ID: g0-gate-dossier.
- Natureza: **consolidação documental. Nenhum código alterado, nenhum teste executado, nenhum log reescrito.**
- Gate G0: **ABERTO. Este dossiê NÃO aprova ACL, transporte, pareamento nem Fase 1.**
- Status deste dossiê: **READY_FOR_T2** = pronto para o Juiz T2 decidir. **Não é APPROVED.**
  `COMPLETED` de spike nunca é lido aqui como `APPROVED` de gate.
- Base de leitura (somente): evidências `22` (quadro), `33` (estático), `34` (regressão final),
  índice das frentes `09`–`32`, `manifest.tsv` do final 34, plano externo (critérios T0/Gate, lido por `sed -n`).
  Nenhum log bruto gigante relido; nenhum inventário reinventado.
- `PROJECT_STATE.md` **existe** (12406 bytes, mtime 22/10) e **está antigo**; não é fonte atual das
  entregas. Atualização dele só após o Juiz aprovar, conforme pedido humano. Não editado aqui.

## 1. Resultado consolidado (contagem corrigida)

- **390 únicos / 456 execuções / 19 arquivos**, 8 comandos exit 0, 0 falhas.
- Correção de aritmética (sem reexecução; logs/TSV intactos): o número 357 anterior excluía o
  Captain inteiro indevidamente. `captain_scope_spec.rb` conta **1× (33) na unicidade (19º arquivo)
  e 3× (33 cada, C1+C2+C3) na execução**.
- Aritmética: execuções 40+27+73+94+123+33+33+33 = **456**; únicos 40+27+73+94+123+33 = **390**;
  19 arquivos (18 + Captain).
- Estático (antes dos 8 lotes): **73 arquivos Ruby, 0 ofensas** (RuboCop check-only `env -i`,
  Ruby 3.4.4, EXIT 0, stderr vazio); `ruby -c` verde; whitespace limpo (conforme evidência 33/34).
- Fonte: `.context/evidence/g0/34-final-regression.md` §§1-2/4 + `34-logs/manifest.tsv` (8 linhas exit 0)
  + `.context/evidence/g0/33-logs/rubocop-final-4.json` (73 arquivos, 0 ofensas).
- Sem inflar Captain (1× na unicidade) nem excluí-lo totalmente (3× na execução).

## 2. Critérios T0.2 / T0.3 / T0.7 → evidências e logs (final 34)

Fonte dos critérios: plano externo §§Fase 0 (T0.2/T0.3/T0.7) e Gate G0 (linhas 617-630):
`/home/thanos/conectacidade/.worktrees/app-solicitacoes/.context/plans/2026-10-22-atendimento-dois-numeros-baileys.md`.
Perguntas EVID: plano §17 (linhas 838-851).

| Critério do plano | Evidência / log final 34 | O que mostra (fato) |
|---|---|---|
| T0.2 — ACL por etapa na inbox física (matriz positiva/negativa superfícies 10.1; membro sem papel não vê nada) | D `34-logs/d-attachment.log` 27/0; B `34-logs/b-leftovers.log` 73/0; G1 `34-logs/g1-scope.log` 94/0; G2 `34-logs/g2-related.log` 123/0; C1-C3 `34-logs/c{1,2,3}-captain-*.log` 33/0 cada | Escopo (policy/query/HTTP/socket/related/notificações/chat interno/agentbot/anexos/inventário) revalidado verde por lotes; G2 fecha as 6 falhas da tarefa 29 (`scope_related_http:368/375/382/389/396` + `route_inventory:204`) — causa provável (não afirmada como prova): correção inbox (ev. 30) + inventário (frente 31), sem bisect para isolar |
| T0.3 — corte temporal (100% antes na origem / depois no destino; nenhuma perdida; nenhuma em ambas) | T `34-logs/t-transfer.log` 40/0 (4 specs: cutover + activation + dispatch + integration) | Transferência/corte revalidada verde; consolidação prévia em `.context/evidence/g0/25-validacao-transferencia.md` (40/0) e instabilidade documentada sem prova nova em `.context/evidence/g0/21-instabilidade.md` |
| T0.7 — barreira de ativação e despacho em voo (pending_activation invisível; worker atrasado não despacha após transferring; nenhuma rota reabre a origem) | T `34-logs/t-transfer.log` 40/0 (mesmo lote: activation + dispatch + integration) | Ativação/despacho/integração verdes no mesmo comando; provas próprias das frentes 16/17/18 citadas na matriz de fontes (§4) |
| Gate G0 — T0.2+T0.3+T0.7 pelo Juiz; EVID-1..8 respondidas ou com decisão explícita de risco | Este dossiê + quadro 22 + decisão R-G0-LOCAL-1 (técnica, ORQUESTRADOR) | G0 só viabilidade; nenhum APPROVED antecipado; Juiz T2 decide todos os critérios |

## 3. Tabela EVID-1..8 → quadro 22 / decisão R-G0

| ID | Status (quadro 22) | Fonte / decisão |
|---|---|---|
| EVID-1 (rotas/serviços) | Respondida (limite: matriz §10.1 literal não validada) | `.context/evidence/g0/22-quadro-evidencias.md` (EVID-1 atualizada: rota nova `connecta_attachments#show` classificada sem inventar total; 877 nativas preservadas) + `.context/evidence/g0/02-inventario-t0-1.md` + `.context/evidence/g0/31-spec-lint.md` §2 + G2 `34-logs/g2-related.log` |
| EVID-2 (versão/digest baileys-api) | NEEDS-T0.6 (desconhecido) | Quadro 22; T0.6 real adiado (só com autorização escrita) |
| EVID-3 (lid/telefone/consolidação) | Parcial (só leitura de código) | Quadro 22; sem prova real; T0.6 pendente |
| EVID-4 (anexos/expiração/rota) | Respondida (Disk local) + rota revalidada em spec (final 34) | Quadro 22 (EVID-4 atualizada) + `.context/evidence/g0/05-evid4-anexos.md` + `.context/evidence/g0/20-t02-anexos.md` §§9-10 + D `34-logs/d-attachment.log` 27/0 |
| EVID-5 (deduplicação pós-reconexão) | Parcial (só leitura de código) | Quadro 22; sem T0.6 não há garantia de exactly-once |
| EVID-6 (AgentBot) | Respondida | Quadro 22 + `.context/evidence/g0/05-evid6-agentbot.md`; achado não corrigido: retry anulado (`webhook_job.rb:4-5`, decisão 11) |
| EVID-7 (recursos próprios: Captain/chat interno/agendadas) | Parcial (c7b código sem prova) | Quadro 22 (EVID-7 atualizada: Captain 33/0 ×3, chat interno no G2 123/0, sub-rotas no B 73/0, conforme logs) + frentes 09/11/12/15/19 |
| EVID-8 (licença/dependências/Redis) | NEEDS-T0.6 (desconhecida) | Quadro 22; nenhuma licença afirmada; T0.6 pendente |
| R-G0-LOCAL-1 | Decisão técnica (ORQUESTRADOR, 2026-10-24), só risco reversível local | Quadro 22 §R-G0-LOCAL-1: cobre só retrabalho local (código local, spike sintético, flags desligadas); **não** é aceite de risco a dados/segurança/produção, nem autorização de uso/distribuição do artefato; **não atribuída ao humano**; transporte real/QR/servidor/produção seguem bloqueados até autorização escrita + T0.6 |

## 4. Fontes de TODAS as frentes 09–34 (papel de entrega + log)

Sem copiar logs inteiros; cada linha cita o papel e o apontador canônico.

| Frente | Papel de entrega | Log / registro |
|---|---|---|
| 09 socket (T0.2-c1) | Eventos conversa/mensagem; c2a/c2b metadados admin | `09-t02-socket.md` + `09-logs/run-7-a-socket.log`, `run-8-b-policy-alone.log`, `run-9-c-combined.log`, `run-c2a-*.log`, `run-c2b-*.log`; final: G1 `34-logs/g1-scope.log` |
| 10 corte (T0.3) | Transação com lock vs Baileys em threads | `10-t02-*.md`/`10-t03-corte.md` + `10-logs/run-17-transfer-final.log`, `run-18-transfer-mais-scope-policy-final.log`; final: T `34-logs/t-transfer.log` |
| 11 Captain (T0.2-c7) | Rotas Captain + vazamento Copilot; histórico instável 2/5 | `11-t02-captain.md` + `11-logs/run-1…5-captain-scope.log`; final: `34-logs/c1/c2/c3-captain-*.log` 33/0 ×3 |
| 12 chat interno (T0.2-c8) | Chat interno NÃO lê conteúdo de conversa (só `InternalChat::*`) | `12-t02-chat-interno.md` + `12-logs/run-1-spec.log`; final: G2 `34-logs/g2-related.log` |
| 13 notificações (T0.2-c4/c5) | Notificações só a quem o Gate permite | `13-t02-notificacoes.md` + `13-logs/c5-run-3-notificacoes.log`, `c5-run-4-regressao.log`; final: G2 `34-logs/g2-related.log` |
| 14 smoke/cutover | Smoke + cutover inicial | `14-logs/cutover-run-1.log`, `smoke-run-1.log`, `smoke-run-2.log` (sem doc 14 próprio; referenciado pelas frentes 10/16) |
| 15 B2 complementos (T0.2-c10) | Admin/integrações/relatórios sob papel nativo; ACHADO-1 | `15-t02-b2-complementos.md` + `15-logs/run-3-b2-complementos.log`; final: B `34-logs/b-leftovers.log` |
| 16 ativação (T0.7a) | Barreira de ativação + despacho em voo | `16-t07a-ativacao.md` + `16-logs/activation-cutover-run-*.log`; final: T `34-logs/t-transfer.log` |
| 17 despacho (T0.7b) | Despacho de saída com barreira | `17-t07b-despacho.md` + `17-logs/run-7-pair-final-restaurado.log`, `run-8-pair-final-409.log`; final: T `34-logs/t-transfer.log` |
| 18 integração (T0.7c) | Integração transferência ↔ despacho (CÓDIGO NÃO VALIDADO na época) | `18-t07c-integracao.md` §5 + `21-instabilidade.md`; final: T `34-logs/t-transfer.log` |
| 19 Captain complemento (c7b) | Hooks Copilot/Captain/inbox (NÃO VALIDADO) | `19-t02-captain-complemento.md` §§1-4/7 (sem `19-logs/`; specs não executadas por instrução do humano) |
| 20 anexos (T0.2-c3) | Rota autorizada de download (código; fix causa-única + admin alinhado) | `20-t02-anexos.md` §§1-10 + `28-logs/anexos-diagnostico.log`, `anexos-final-3.log`, `anexos-final-4.log` (27/0); final: D `34-logs/d-attachment.log` 27/0 |
| 21 instabilidade (T0.7c-2) | Hipótese concorrência + achado sem `account_id` (SEM prova nova) | `21-instabilidade.md` + `21-logs/serial-summary.tsv`, `policy-alone-*.log` |
| 22 quadro | Quadro EVID-1..8 + R-G0-LOCAL-1 (atualizado: fatos EVID-1/4/7 do final 34) | `22-quadro-evidencias.md` (este dossiê preserva decisão e histórico) |
| 23 team/contato (T0.2-c6a) | Guarda 422 team_id (IMPLEMENTADO / NÃO VALIDADO na época) | `23-t02-team-contato.md` (sem `23-logs/`); final: B `34-logs/b-leftovers.log` 73/0 |
| 24 sub-rotas (T0.2-c9) | 11 sub-rotas B1 + bulk (spec escrita, NÃO EXECUTADA na época) | `24-t02-subrotas.md` (sem `24-logs/`); final: B `34-logs/b-leftovers.log` 73/0 |
| 25 validação transferência | T0.3/T0.7 validação 40/0 (diagnóstico) | `25-validacao-transferencia.md` + `25-logs/transfer-final-1.log`; final: T `34-logs/t-transfer.log` |
| 26 validação escopo novo | Captain/anexos/B1/team/B2 por lotes (A com falhas mapeadas, B verde; 2ª rodada A parcial/B verde) | `26-validacao-escopo-novo.md` + `26-logs/escopo-lote-a-{1,2}.log`, `escopo-lote-b-{1,2}.log`; superado pelo final 34 |
| 27 correções specs | Fixes de setup/expressão/contrato no lote B (só specs) | `27-correcoes-specs.md` (sem `27-logs/`); revalidado no B 73/0 final |
| 28 anexos pós-26 | Fix causa-única + admin alinhado 27/0 | `20-t02-anexos.md` §§9-10 + `28-logs/anexos-final-4.log`; final: D `34-logs/d-attachment.log` 27/0 |
| 29 regressão+lint | Regressão G1 verde / G2 6 falhas + Captain 3× + RuboCop 90 ofensas (diagnóstico) | `29-regressao-lint.md` + `29-logs/g1-lote-1.log`, `g2-lote-1.log`, `captain-run-{1,2,3}.log`, `rubocop-final-1.json`; G2 superado pelo final 34 |
| 30 inbox | Gate da inbox marcada restaurado (código, NÃO VALIDADO na época) | `30-correcoes-inbox.md` (sem `30-logs/`); revalidado no G2 123/0 final (causa provável, sem bisect) |
| 31 spec-lint | 5 specs zerados + rota nova classificada | `31-spec-lint.md` + `31-logs/spec-lint.json`, `spec-lint.log`; revalidado no final 34 (D/B/C/G2) |
| 32 transfer-lint | Transfer 11 arquivos zerados (`next WAIT`) | `32-transfer-lint.md` + `32-logs/transfer-lint.json`, `transfer-lint.log`; revalidado no T 40/0 final |
| 33 scope-lint | Estático parcial → final 73/0 (disable local socket + checks) | `33-scope-lint.md` §§1-17 + `33-logs/rubocop-final-4.json` (73/0), `rubocop-final-4.log`, `syntax-whitespace-summary.log` |
| 34 regressão final | 8 lotes 456/0 + matriz 19 + estático 73/0 | `34-final-regression.md` + `34-logs/{t-transfer,d-attachment,b-leftovers,g1-scope,g2-related,c1-captain-1,c2-captain-2,c3-captain-3}.log` + `34-logs/manifest.tsv` |

## 5. Comandos zerados (8) + estático

| # | Lote | Log | Ex | Fa |
|---|---|---|---|---|
| T | transfer (4 specs) | `34-logs/t-transfer.log` | 40 | 0 |
| D | download | `34-logs/d-attachment.log` | 27 | 0 |
| B | b1+team+b2 | `34-logs/b-leftovers.log` | 73 | 0 |
| G1 | policy+http+socket | `34-logs/g1-scope.log` | 94 | 0 |
| G2 | related+notifications+internal+agentbot+access+inventory+smoke | `34-logs/g2-related.log` | 123 | 0 |
| C1 | captain sozinha (1ª) | `34-logs/c1-captain-1.log` | 33 | 0 |
| C2 | captain sozinha (2ª) | `34-logs/c2-captain-2.log` | 33 | 0 |
| C3 | captain sozinha (3ª) | `34-logs/c3-captain-3.log` | 33 | 0 |
| — | RuboCop 73 arquivos | `33-logs/rubocop-final-4.json` | 0 ofensas | — |

Padrão de comando (prefixo comum): `cd /home/thanos/chatwootnext-connecta-g0-prep &&
PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:$PATH
... flock -w 900 .../spec.lock timeout 300 scripts/connecta/g0_test_env.sh --spec --apply <specs>`
(comando completo no §1 de cada log; janela 2026-10-24T19:11:26Z → 19:19:02Z; TSV incremental
`34-logs/manifest.tsv`). Sintaxe/whitespace conforme 33 (counts, sem colar 73 OK).

## 6. Limites honestos já identificados (não corrigir aqui)

1. **Decisões 8–11 do `PROJECT_STATE.md` (2026-10-22), todas pendentes:** (8) super admin com rotas
   Devise públicas; (9) `/auth/:provider` sem `redirect_whitelist`; (10) teardown+preparo recusa volume
   órfão (recomendado manter recusa); (11) retry genérico do AgentBot (recomendado manter 1 tentativa).
   Fonte: `.context/PROJECT_STATE.md` (antigo; não editado) + quadro 22 §Achados.
2. **Presença: fato vs. possibilidade.** FATO (ev. 09 §8.5): `room_channel.rb:19-25` envia
   `{account_id, users: {id: disponibilidade}, contacts: {id: 'online'}}` ao próprio assinante sem
   passar pelo listener/hook, sem spec. POSSIBILIDADE (sinal, não conteúdo): ids de contatos podem
   incluir vinculados à inbox marcada. Decisão pendente: filtrar `contacts` por `ContactVisibility`.
3. **Frontend com admin metadata untested:** nenhum cliente testado com os metadados reduzidos
   `{id, conversation_id/inbox_id, status, org_unit_id, account_id}` (ev. 09 §7.4); componente que
   espera `messages`/`meta` pode quebrar com o campo ausente.
4. **Job admin separado:** `ActionCableBroadcastJob:26` relê `conversation.push_event_data` e trocaria o
   payload reduzido pelo completo; o spike usa `AdminMetadataBroadcastJob` próprio. Produção exige
   decisão: (A) job próprio ou (B) alterar o job nativo (core, fora do escopo).
5. **`POST contacts` com `inbox_id` da inbox marcada não coberto** (ev. 15 §4): passa por
   `ContactInboxBuilder` com `validate_baileys_phone: true`, pode chegar ao transporte; exige stub de
   transporte e decisão de escopo. Criação sem `inbox_id` provada (ev. 15 §1).
6. **T0.6 real adiado:** EVID-2/8 NEEDS-T0.6; EVID-3/5 parciais por código; pin/digest/compatibilidade/
   licença/dependências/Redis/recursos desconhecidos; transporte real/QR/servidor/produção só com
   autorização escrita. Fluxo G0 é só viabilidade.
7. **Fluxo G0 só viabilidade:** nenhuma produção/deploy/commit/QR. `git status` mostra só os 7 grupos
   `??` pré-existentes (`.context/`, `app/services/connecta/scope/`, `app/services/connecta/transfer/`,
   `scripts/`, `spec/connecta/`, `spec/requests/connecta/`, `spec/support/connecta/`); nenhum commit feito.

## 7. Apontadores canônicos (preservados, não copiados)

- Quadro: `.context/evidence/g0/22-quadro-evidencias.md` (EVID, R-G0-LOCAL-1, achados, honestidade).
- Regressão: `.context/evidence/g0/34-final-regression.md` + `34-logs/manifest.tsv` + 8 logs.
- Estático: `.context/evidence/g0/33-scope-lint.md` (§§16-17) + `33-logs/rubocop-final-4.json` (73/0).
- Critérios: plano externo §§Fase 0/Gate (linhas 617-630) e §17 (linhas 838-851):
  `/home/thanos/conectacidade/.worktrees/app-solicitacoes/.context/plans/2026-10-22-atendimento-dois-numeros-baileys.md`.
- Estado antigo: `.context/PROJECT_STATE.md` (22/10; não editado; atualizar só após Juiz aprovar).
- Logs Coder finais: `/home/thanos/.local/state/opencode-coder/20261024T190959-1330268`
  (todas as execuções verdes; 357 no relatório era erro de aritmética, corrigido aqui).

## 8. Pedido ao Juiz T2 (sem veredito antecipado)

Dossiê factual **READY_FOR_T2**: 390 únicos / 456 execuções / 19 arquivos, 8 comandos zerados,
73 Ruby RuboCop 0, T0.2/T0.3/T0.7 com fontes, EVID desconhecidas e decisão de escopo local
preservadas, limites listados. **O Juiz T2 decide todos os critérios; nada aqui é APPROVED.**
