# 003 — Escopo de contato na busca e leitura em manutenção (spike G0)

## Contexto
Os specs de RF1 (busca de contatos) e de contenção (`maintenance`) esperavam resultados que não seguem as regras já registradas no projeto. O código estava certo; as expectativas dos specs estavam erradas.

## Decisão
1. **Contato sem vínculo com inbox marcada é nativo e visível** na busca. Contato **com** vínculo (`ContactInbox`) em inbox marcada só aparece a quem vê alguma conversa dele nessa inbox. Fonte: `.context/evidence/g0/36-rf1-search.md` §22-28 ("só o próprio + unmarked"). Implementação: `app/services/connecta/scope/contact_visibility.rb:14-19`.
2. **Manutenção nega leitura de não-admin com 404**, sem revelar a conversa. Envio humano continua 409 e entrada recebida continua gravada. Fonte: `.context/decisions/002-negacao-http-escopada-g0.md` §Decisão (leitura negada em manutenção = 404). Implementação: `app/services/connecta/scope/gate.rb:106-115`.

## Consequências
- `spec/connecta/captain_scope_spec.rb`: asserções de RF1 alinhadas à regra 1.
- `spec/connecta/containment_spec.rb`: leitura de não-admin em manutenção espera 404 (regra 2).
- `spec/connecta/scope_socket_delivery_spec.rb`: epoch lido do usuário dentro de `users: [[id, epoch]]` (contrato real; só `kind: notification` tem epoch no topo).

## Alternativas consideradas
- Mudar o código para negar contato sem vínculo: rejeitado; contraria a evidência 36 (RF1) e tornaria contatos nativos invisíveis.
- Manter 200 para não-admin em manutenção: rejeitado; contraria a decisão 002, que trata manutenção como leitura negada.

## Adendo: TTL de heartbeat da ACL (FORK-v7b)
- **Fonte WP:** `apps/whatsapp-platform/src/config.ts:156` — `CONNECTA_ACL_HEARTBEAT_MAX_AGE_SEC` (`aclHeartbeatMaxAgeSec`), padrão 120 s (faixa 30–3600). Envio do heartbeat: `src/services/humanService/runtime.ts:62` a cada `max(10 s, aclHeartbeatMaxAgeSec/3)` = 40 s com o padrão.
- **Antes no fork:** `g0_adapter.rb` usava `CONNECTA_ACL_HEARTBEAT_TTL_SEC` com padrão 60 s; `projection.rb` usava 300 s fixos. Com 60 s e envio a cada 40 s o fork ficaria stale entre envios; os dois valores divergiam.
- **Decisão:** uma única fonte no fork, `Connecta::Scope::Projection.heartbeat_ttl`, lendo `CONNECTA_ACL_HEARTBEAT_TTL_SEC` com padrão **120 s** (= `aclHeartbeatMaxAgeSec` do WP, ou seja, 3 × 40 s de envio). Ambos os pontos (`Projection#fresh?` e `ProjectionTablesHook#fresh?`) usam essa função.
- **Consequência:** o fork expira no mesmo tempo que a plataforma considera o heartbeat válido; não expira antes de ~3 ciclos de envio. Quem define a janela real em produção é o `CONNECTA_ACL_HEARTBEAT_MAX_AGE_SEC` do WP; o fork deve usar o mesmo valor em `CONNECTA_ACL_HEARTBEAT_TTL_SEC`.
