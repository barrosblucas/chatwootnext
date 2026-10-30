# 52 — RF2 socket, RF4 notifications/entrega e RF5 socket (código escrito; runtime pendente)

## Implementado

- RF2 socket: `ContactDataProjection.socket_payload` copia Hash/Array e remove `notes`/`custom_attributes` somente de DTOs `type: contact` vinculados a inbox marcada. `ContactPushProjectionHook` projeta o DTO nativo; `SocketHook` e `BroadcastJobGuard` aplicam a projeção antes do enqueue e após `prepare_broadcast_data` recarregar a conversa.
- RF4 HTTP: `NotificationVisibility` filtra a relation do `NotificationFinder` antes de paginação/contagem e `NotificationsControllerHook` retorna 404 para ações em notificação oculta.
- RF4 entrega: `DeliveryBinding` captura contexto antes do enqueue e preserva `connecta_scope` em serialize/deserialize/retry. Push/email são revalidados por epoch, registro atual e Gate; e-mail marcado usa `deliver_now`, com guarda adicional `before_deliver`.
- RF5 conversa/notificação: `SocketHook` anexa contexto aos broadcasts, inclusive menções e eventos `notification.created`/`notification.updated`; o job filtra recipients antes de qualquer reload e projeta o payload recarregado. Admins recebem somente metadados com papel/epoch revalidados.
- RF5 contato: `Gate#scope_readable?` e a chave transitória `CONTACT_DELIVERY_KEY` preservam classificação e leitores autorizados antes de `Contact.destroy`; a chave antiga `CONTACT_SNAPSHOT_KEY` manteve o formato existente.
- Installer test-only mantém o guard `Rails.env.test?`, o guard de criação RF3 e os filtros existentes RF1. Specs G0 preexistentes foram preservadas e não foram executadas.

## Validação estática

- `ruby -c` 3.4.4 nos 17 arquivos de código alterados: `Syntax OK`.
- RuboCop nos mesmos 17 arquivos: sem offenses.
- `git diff --check` para arquivos rastreados e checagem `--no-index --check` para os arquivos G0 untracked: sem problemas de whitespace.
- Nenhum RSpec, build ou verificação funcional executado, conforme restrição de execução faseada.

## Limites

O comportamento foi implementado, mas permanece sem validação runtime; não afirmar RF2/RF4/RF5 aprovadas. A aprovação consolidada do G0 continua pendente do coordenador e do Juiz no encerramento.
