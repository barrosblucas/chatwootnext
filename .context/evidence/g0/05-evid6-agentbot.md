# EVID6 — Entrega de eventos ao AgentBot (T0.5)

- Data (UTC): 2026-10-22, de 15:52Z a 15:56Z.
- Alvo: o mesmo da EVID4 (local, Postgres e Redis do projeto G0, dados sintéticos).
- Listener, job e `Webhooks::Trigger` são os reais. **Único ponto stubado de rede: `SafeFetch.fetch`**, que não faz rede. `GlobalConfig.get_value` é stubado só para `WEBHOOK_TIMEOUT`, nos exemplos de timeout. URLs são `*.example.test`.
- Estado do gate: **G0 ABERTO**. Esta evidência não aprova transporte, pareamento nem Fase 1.

## 1. Execução

Comando e resultados: os mesmos da EVID4 (`05-evid4-anexos.md`, seção 1). A suíte `agent_bot_delivery_spec.rb` tem 17 exemplos. Nas rodadas finais (`05-logs/run-4-specs.log` e `run-5-specs.log`, exit 0, 29 exemplos com as specs de anexos, 0 falhas) ela passou. A rodada 1 (`run-1-specs.log`) é anterior à correção do exemplo de timeout e à asserção de `Content-Type`. Lint: `bundle exec rubocop` nas duas specs e no guard, exit 0, sem ofensas (`05-logs/rubocop-specs.log`). Verificação de espaços e de newline final nos arquivos novos e editados: sem problemas.

## 2. Observado no código e nos exemplos

| Ponto | Código | Exemplo que prova |
|---|---|---|
| Seleção: `[assignee, inbox].compact.uniq`. O bot da caixa só entra com `agent_bot_inbox` ativo | `app/listeners/agent_bot_listener.rb:65-77` | "enqueues assignee before the inbox bot, one job per bot"; "does not duplicate the delivery" |
| Um job por bot, fila `high`, com secret e `delivery_id` (UUID gerado por bot a cada evento) | `agent_bot_listener.rb:85-90`; `app/jobs/agent_bots/webhook_job.rb:2` | "gives each bot its own delivery_id for the same event" |
| Corpo JSON e assinatura exata: `X-Chatwoot-Signature = sha256=HMAC-SHA256(secret, "<timestamp>.<body>")` em hex | `lib/webhooks/trigger.rb:43, 55-64` | "sends JSON with HMAC-SHA256 over the exact…" |
| Cabeçalhos: `X-Chatwoot-Timestamp` (epoch em segundos), `X-Chatwoot-Signature`, `X-Chatwoot-Delivery`, `Content-Type` e `Accept` `application/json` | `trigger.rb:55-64` | o mesmo exemplo |
| Timeout de abertura e de leitura: `WEBHOOK_TIMEOUT` se positivo; senão 5 s | `trigger.rb:119-124` | "uses the 5-second default…"; "uses WEBHOOK_TIMEOUT when it is configured" (12 s) |
| Estabilidade do `delivery_id` em retry; timestamp e assinatura mudam a cada tentativa | `trigger.rb:59` (timestamp por request); `delivery_id` vem nos argumentos do job | "keeps delivery_id across attempts, but timestamp and signature change per attempt" |

### Retries e esgotamento

| Caso | Tentativas observadas | Efeito na conversa | Origem |
|---|---|---|---|
| 429 | 3 execuções no total (base, +4 s, +8 s; o retry agenda com 3 s de espera) | `pending` até a última falha; `open` depois do esgotamento, com mensagem de atividade | `trigger.rb:126-128` (`RETRYABLE_AGENT_BOT_STATUSES = [429, 500]`); `agent_bots/webhook_job.rb:3` (`retry_on … wait: 3.seconds, attempts: 3`) |
| 500 | igual ao 429 | igual | igual |
| 429/500 com `keep_pending_on_bot_failure` | 3 | continua `pending` | `trigger.rb:81` |
| 404 | 1 | `open` na 1ª tentativa | `trigger.rb:28-32` |
| Timeout de rede (FetchError) | 1 | `open` na 1ª tentativa | idem |

Os exemplos de 404 e de timeout drenam a fila inteira (`perform_enqueued_jobs` sem `at:`, que também executa jobs agendados no futuro). Se houvesse um retry agendado, ele entraria como 2ª entrega. Por isso esses dois exemplos provam a ausência de retry. Antes da correção, o exemplo de timeout só rodava até `base_time`, e um retry de +3 s não seria executado: esse exemplo não provava nada sobre retry.

## 3. Achado: retry declarado e não ativo para erros genéricos

- `AgentBots::WebhookJob` herda de `WebhookJob`. O pai declara `retry_on CustomExceptions::Webhook::RetriableError, attempts: 5` (`app/jobs/webhook_job.rb:4`) e, logo depois, `discard_on` para a mesma classe (`webhook_job.rb:5`).
- O ActiveSupport procura o handler do último para o primeiro (`activesupport-7.1.5.2/lib/active_support/rescuable.rb:129`, `rescue_handlers.reverse_each`). Então o `discard_on` vence e nunca há retry.
- Efeito medido: erros que não são 429/500 (404, timeout de rede, outros 5xx) geram 1 execução e nada mais. Os exemplos "does not retry: one attempt per job even after draining the queue" (404) e "is treated as a common failure… no retry is scheduled" (timeout) provam isso.
- Outros 5xx além de 500 (502, 503 etc.) também caem nesse caminho: `RETRYABLE_AGENT_BOT_STATUSES` só inclui 429 e 500. Não foi medido por exemplo.
- Pela mesma regra, o retry de 5 tentativas declarado em `WebhookJob` para webhooks de conta também não se ativa. Isso não foi medido: não há spec de conta nesta suíte.
- **Não corrigido**: o app está fora do escopo desta tarefa. Decidir se timeouts devem ser retentados é uma escolha de produto. A correção é trocar a ordem de declaração ou o tipo de handler. Exige mudança de app autorizada.
- O `discard_on` também chama `Webhooks::ErrorHandler.perform` (`webhook_job.rb:5-11`). Não foi medido aqui.

## 4. Ordem e entrega: o que está e o que não está provado

- **Provado**: a seleção é `[assignee, inbox]` sem duplicata, e a enfileiração segue essa ordem.
- **Não é garantia de ordem global de entrega.** O exemplo "completion order inverts the selection" mostra o bot da caixa concluindo antes do retry do assignee. A ordem de conclusão depende de retries, de workers e do tempo de cada bot.
- **Exactly-once não está provado.** Os exemplos mostram uma entrega por bot quando a resposta é 2xx, e 3 tentativas quando a resposta é 429/500. Se o bot processar e responder 500 (ou se o timeout ocorrer depois do processamento), o retry reprocessa. O `delivery_id` estável permite ao receptor deduplicar, mas Chatwoot não garante isso e o receptor não foi testado.
- **Nada disso foi provado do lado do receptor**: as specs geram a assinatura e a comparam com o valor esperado, mas não validam uma implementação de receptor real.

## 5. Limitações

- `SafeFetch` está stubado em todos os exemplos. Por isso, a lógica própria dele (`lib/safe_fetch.rb`, incluindo timeouts reais e bloqueio de destinos) **não está coberta por esta evidência**.
- O "relógio" dos retries é simulado com `travel_to` e `perform_enqueued_jobs(at:)`. Concorrência real de workers não foi medida.
- Specs existentes de `Webhooks::Trigger` e `AgentBots::WebhookJob` não foram executadas: fora da allowlist do launcher (ver EVID4, seção 1).
- Sem mutação de propósito (teste de sensibilidade) nas specs: o app não podia ser alterado. A prova vem da leitura do código e de exemplos que passam no código real.
