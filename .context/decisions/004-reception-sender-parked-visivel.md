# 004 — Envio em recepção só pelo usuário de serviço; parked vira falha visível (menos em manutenção)

## Contexto
Mensagens de saída do bot ("Conecta Cidade Bot", usuário de serviço) em conversas no estado `reception` (antes da escolha de setor) ficavam `parked` silenciosamente: o `CLAIM_SQL` (base em `app/services/connecta/transfer/outbound_dispatch.rb` e patcheado em `app/services/connecta/runtime/g0_adapter.rb:patch_outbound_claim`) só liberava `s.state = 'active'`. Sintoma: humano manda "oi" no número humano e não recebe o menu de triagem. Decisões humanas (2026-11-02): "Só o usuário do bot" (atendentes, inclusive admins, continuam travados até o setor ser definido); "Mostrar erro na espera" (parked aparece como falha no Chatwoot); variável com o id do usuário de serviço.

## Decisão
1. **Nova configuração `CONNECTA_RECEPTION_SENDER_USER_IDS`** (ids separados por vírgula; vazia/ausente = nada liberado, comportamento atual). Leitura centralizada em `Connecta::Runtime::Feature.reception_sender_user_ids` (onde as demais `CONNECTA_*` são lidas), com parse tolerante (ignora vazio/inválido/não positivo, deduplica).
2. **Regra do claim (nos dois SQLs, coerentemente):** libera quando inbox em enforcement válido e sem manutenção E (`s.state = 'active'` OU (`s.state = 'reception'` E `m.sender_type = 'User'` E `m.sender_id IN (<ids>)`)), com `JOIN messages AS m ON m.id = d.message_id` — verificação no servidor pelos campos persistidos da mensagem (sender), NUNCA por `content_attributes`. Os ids entram como parâmetro (`IN (?)`); vazio vira `IN (NULL)` e nunca libera. Mensagens privadas/notas continuam fora (`dispatchable?` inalterado). `transferring` e demais estados continuam `parked`.
3. **Parked visível:** `SendReplyHook` chama `OutboundDispatch.mark_parked_visible!` quando o claim estaciona: marca a mensagem `failed` com `content_attributes.external_error` = `PARKED_VISIBLE_ERROR` ("Mensagem não enviada: o atendimento ainda não tem setor definido (recepção) ou está em transferência."). **Exceção manutenção:** com a inbox em modo manutenção (`maintenance` ou `enforcement = 'maintenance'`), NÃO marca — o fluxo de manutenção nega na superfície HTTP (409) e o parked do claim é barreira temporária; marcar failed pareceria erro do agente. Não há re-despacho de parked após manutenção no código (parked é terminal na linha de despacho); portanto a exceção é só sobre não marcar, sem preservar fila alguma.
4. **Isolamento por setor inalterado:** a exceção vale só para `reception` (sem setor definido, nada para vazar) e só para remetentes configurados; `Gate` e escrita humana não mudam.

## Consequências
- `app/services/connecta/transfer/outbound_dispatch.rb`: `CLAIM_SQL` + `claim!` (parâmetro de ids) + `mark_parked_visible!`/`maintenance_parked?` + `PARKED_VISIBLE_ERROR`.
- `app/services/connecta/runtime/g0_adapter.rb:patch_outbound_claim`: mesmo predicado nas tabelas de produto.
- `app/services/connecta/runtime/feature.rb`: `reception_sender_user_ids`.
- `app/services/connecta/transfer/send_reply_hook.rb`: parked chama `mark_parked_visible!` e retorna.
- `spec/connecta/outbound_dispatch_spec.rb`: recepção (configurado/outro/admin/vazia), transferring, manutenção, parse da config.
- `docker-compose.teste-lan.human-number-override.yml`: `CONNECTA_RECEPTION_SENDER_USER_IDS=5` em rails e sidekiq (teste LAN; produção define o id do usuário de serviço real).

## Alternativas consideradas
- Checar permissão por `content_attributes`: rejeitado; conteúdo é editável pelo cliente, sender persistido é autoridade do servidor.
- Marcar failed também em manutenção: rejeitado; quebraria o fluxo de manutenção (409 na superfície) com falso erro do agente.
- Re-despachar parked ao sair de manutenção: rejeitado; não existe esse fluxo no código e criaria risco de envio duplicado.
