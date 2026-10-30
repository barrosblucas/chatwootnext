# 002 — Negação HTTP escopada no spike G0 (404 leitura, 403 escrita, 401 não autenticado)

## Contexto
O spike de escopo (T0.2 parte A) negava com `Pundit::NotAuthorizedError`, que o `handle_with_exception` global transforma em 401. Um usuário autenticado sem acesso recebia 401, igual a um não autenticado, e o 401 confirma que a conversa existe. O briefing da parte B1 pede 403 ou 404 para autenticados e preserva 401 para não autenticados, sem mudar o `rescue` global produtivo.

## Decisão
- Leitura negada em inbox marcada (conversa de outro setor, fora de estado, sem grant, admin_only, manutenção, heartbeat vencido): **404** com a mesma mensagem de não encontrado. A conversa não é revelada.
- Escrita negada em inbox marcada (gestor, membro sem grant, transferring, `case_version` inválida, admin nominal): **403**.
- Criação de conversa em inbox marcada: **403** para todos (admin inclusive, pois o admin só lê), antes de qualquer I/O. Vale para `inbox_id` e para o inbox alcançado por `source_id`.
- Não autenticado: 401 nativo, preservado. O guard de criação roda antes da autenticação, então retorna sem negar quando `current_user` é nil.
- A negação é renderizada por `rescue_from` nos controllers do spike (`Connecta::Scope::Denied`), não por mudança no `RequestExceptionHandler`.
- Admin nominal na listagem: não recebe linhas da inbox marcada. O conteúdo de cada conversa sai só pelo detalhe, auditado por conversa. A listagem gera registro com `conversation_id` nulo, que prova só a consulta.

## Alternativas consideradas
- Manter 401 e marcar como "negado" no log: rejeitado; não atende a AC3 e mantém o vazamento de existência.
- Mapear toda negação para 404: rejeitado para escrita; o gestor que lê a conversa deve saber que não pode escrever (403 é mais útil e não revela nada que ele já leu).
- Admin com listagem auditada por linha: rejeitado nesta fase; exigiria auditar a página inteira com custo e não resolve o registro de contagem. O admin lê por detalhe auditado.

## Consequências
- Escopo do spike: os hooks só são instalados em `Rails.env.test?` (`app/services/connecta/scope/installer.rb`). Produção não muda.
- Specs da parte A alinhados: leituras negadas 401→404, escritas negadas 401→403 (`spec/connecta/scope_policy_query_spec.rb`). Nenhuma negação foi enfraquecida.
- Guarda de escrita genérica para toda rota aninhada de conversa (não GET): fail-closed. Leituras POST sem conversa (`filter`, `presence_subscribe_bulk`) não passam pelo guard.
- Pendente: `GET conversations/unread_counts` tem contador próprio (Redis) que não passa pelo escopo; a flag `conversation_unread_counts` está desligada por padrão (`config/features.yml:28-30`).

## Superseding (2026-10-28 — pedido funcional "todos os usuários podem iniciar conversas")
- A regra de 2026-10-22 "criação em inbox marcada: 403 para todos" está SUBSTITUÍDA: a criação em inbox marcada segue a autorização NATIVA de inbox (`authorize @inbox, :show?` / `authorize @contact_inbox.inbox, :show?` em `conversations_controller.rb:218-239`). O guard customizado `connecta_scope_create_guard!` foi REMOVIDO (`conversation_http_hook.rb`, `scope/installer.rb:40`).
- Quem pode criar: qualquer usuário autenticado com membership nativa na inbox (agente membro, admin nativo same-account). Não inclui anônimos (401 nativo) nem usuários fora da conta/sem inbox (401/404 nativo, sem conversa criada em alvo indevido).
- Nenhuma allowlist nova, nenhuma exceção só-admin, nenhum bypass de `source_id`: a fronteira de conta continua `Current.account` + `assigned_inboxes` nativos. Leitura/escrita/transferência seguem inalteradas (guard de escrita, 404/403 de leitura/escrita, transfer guard).
- `source_id` continua resolvido pelo controller nativo; `source_id` de outra conta não atravessa a fronteira (401/404 nativo, nada criado).
- Leitura posterior/escopo de recepção: a conversa criada recebe escopo via `ReceptionScopeCreator`; o acesso seguinte segue o Gate (não expandido por esta mudança).

Status: **Aceita com superseding de 2026-10-28** (substitui a proibição de criação; restante da decisão vigente).
Ver também `.context/decisions/001-runner-aceita-extras-g0.md` e `.context/evidence/g0/07-scope-http-filter.md`.
