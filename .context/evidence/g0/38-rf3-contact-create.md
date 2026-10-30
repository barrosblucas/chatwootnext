# 38 — RF3 criação de contato com inbox marcada (TASK_ID g0-rf3-create-spec) — MATRIZ NÃO EXECUTADA

Somente RF3 (juiz R1 §RF3: `POST contacts` com telefone + `inbox_id` marcado contorna o guard
do provedor). Arquivos novos SÓ: `spec/connecta/scope_contact_create_spec.rb` + este doc + append
changelog. Guard (ContactHook) fica em frente independente; esta entrega NÃO lê/edita ContactHook
em mutação e não depende de helpers novos. Nativo/Core lidos somente: controller, builder,
policy, fixtures, factories, rotas. Coder do NotificationDeliverySpec NÃO tocado.
ESCRITO e NÃO EXECUTADO — execução pendente na validação consolidada.

## 1. Contrato nativo (somente leitura nesta tarefa)

| Superfície | Fonte | Fato |
|---|---|---|
| POST contacts | `app/controllers/api/v1/accounts/contacts_controller.rb:94-105` | `create` salva `@contact`, chama `build_contact_inbox` (com `inbox_id`) e `process_avatar_from_url`; `permitted_params` inclui `name/identifier/email/phone_number`. |
| build_contact_inbox | `.../contacts_controller.rb:184-192` | Retorna cedo sem `inbox_id`; senão `Current.account.inboxes.find` (outra conta/inexistente → `RecordNotFound` → 404) e `ContactInboxBuilder.new(..., validate_baileys_phone: true).perform`. |
| Builder Baileys | `app/builders/contact_inbox_builder.rb:33-76` | `normalize_phone_for_baileys!` só para inbox WhatsApp Baileys; chama `on_whatsapp(phone)` na shape `{'exists', 'jid'}`; canônico diferente realinha o contato e, se o canônico já existe em outro contato da conta, faz `ContactMergeAction` (merge) senão `update!(phone)`. Erro de lookup do provedor é engolido (`rescue → nil`); erro de escrita/merge propaga. |
| Transporte real | `app/models/channel/whatsapp.rb:334-338` + `app/services/whatsapp/providers/whatsapp_baileys_service.rb:491-509` | `Channel::Whatsapp#on_whatsapp` delega ao `provider_service.on_whatsapp`, que faz `POST <provider>/connections/<phone>/on-whatsapp` com `{jids: [remote_jid]}` e devolve `result.first` ou `{'jid', 'exists' => false}` (fallback sem rede neste spec via stub de método, sem HTTParty/WebMock). |
| Autorização nativa | `app/controllers/api/v1/accounts/contacts_controller.rb:17` (`before_action :check_authorization`) + `app/policies/contact_policy.rb:42` (`create?` → `true`) + `app/controllers/api/base_controller.rb:14-19` | Criação é permitida a qualquer membro autenticado da conta; o guard de escopo (outra frente) nega antes. Sem usuário → 401 nativo preservado (não coberto aqui; guard futuro retorna sem negar sem `current_user`, padrão do `conversation_http_hook`). |
| Erros nativos | `app/controllers/concerns/request_exception_handler.rb:18-27` | `RecordNotFound` → 404 (`Resource could not be found`); `Pundit::NotAuthorizedError` → 401 nativo. O guard de escopo desta frente nega create em marcada com **403** (escrita: mesmo padrão de `contact_team`/`contact_attrs` 403 da B2 e `contact_notes` escrita 403) e reserva o 404 ao nativo (inbox de outra conta/inexistente) e à leitura. |
| Rota nativa | `config/routes.rb:256` | `resources :contacts, only: [:index, :show, :update, :create, :destroy]` → `POST /api/v1/accounts/:account_id/contacts` existe; caso 1 prova via `recognize_path` (não confundir 403/404 de ACL com rota inexistente). |
| Resposta create | `app/views/api/v1/accounts/contacts/create.json.jbuilder:1-10` | `payload.contact` (partial `_contact`, com `contact_inboxes` quando `with_contact_inboxes`) + `payload.contact_inbox` (`inbox`, `source_id`). Positivo nominal asserta `source_id` sem `+` (shape Baileys). |
| Fixture/atores | `spec/connecta/support/g0_scope_fixture.rb` | Mesma WhatsApp Baileys (`marked_inbox`), controle não marcada, `agent_a` (atender A), `agent_b` (atender B), `manager_a` (acompanhar A), `member_without_grant`, `admin_nominal` (grant `admin_nominal` na raiz), `contact_control`/`control_inbox` (unmarked). Admin nativo (`role: :administrator`, sem grant nominal) criado no exemplo via factory estável `spec/factories/users.rb:32-33`. Telefone válido E164 `+\[1-9]\d{1,14}` (`app/models/contact.rb:56-58`); unicidade por conta (`scope: [:account_id]`). |

## 2. Matriz de casos (12 exemplos, todos NÃO EXECUTADOS)

| # | Superfície | Ator / entrada | Esperado |
|---|---|---|---|
| 1 | rota | — | `recognize_path(contacts_path, post)` → `contacts#create` (controle positivo: negações abaixo são ACL, não rota inexistente). |
| 2 | `POST contacts` + marcada própria | membro sem grant, telefone novo | **403** + `Contact.count` e `ContactInbox.count` inalterados + **zero `on_whatsapp`** (spy `have_received` no `Channel::Whatsapp`, shape stubada `{'exists' => false, 'jid'}` sem rede). |
| 3 | idem | outro setor (atender B) | 403 + sem Contact/ContactInbox novo + zero provedor. |
| 4 | idem | gestor (acompanhar) | 403 + sem efeito + zero provedor. |
| 5 | idem | atender do próprio setor sem nominal | 403 + sem efeito + zero provedor (atender ≠ criar com marcada). |
| 6 | idem | admin nativo sem grant nominal | 403 + sem efeito + zero provedor (AC2: nativo NÃO ganha permissão nova). |
| 7 | idem, telefone já existente | membro, phone do dono `RF3 Dono` | 403 + counts inalterados + dono intacto (`name`, `custom_attributes` crus) + zero provedor (AC1: cobre `phone_number` existente, sem merge/atualização). |
| 8 | inbox de outra conta | A, `inbox_id` de outra `account` | **404 nativo** (via `Current.account.inboxes.find`) + sem efeito + zero provedor. |
| 9 | `inbox_id` inexistente | A, `999_999_999` | 404 nativo + sem efeito + zero provedor (prova que 403 dos casos 2–7 não é 404 de rota). |
| 10 | positiva nominal | admin nominal, marcada, shape `{'exists' => false}` | **200** + `Contact +1`, `ContactInbox +1`, `contact_inbox.source_id` sem `+` (AC2: caminho autorizado com shape real, sem transporte real). |
| 11 | controle unmarked | membro, `control_inbox` | 200 + `Contact +1`, `ContactInbox +1` (AC2: inbox própria sem marca preserva nativo). |
| 12 | controle genérico | membro, sem `inbox_id` | 200 + `Contact +1`, `ContactInbox +0` (AC2: create sem inbox preserva nativo). |

Não ampliado: 401 sem token (nativo preservado, guard futuro retorna sem negar); avatar/`source_id` explícito/`identifier`/email-duplicado (fora do RF3); socket/jobs de contato (RF2/RF5); merge canônico positivo (só a negação do merge é provada aqui).

## 3. Limites honestos

- Guard (ContactHook) NÃO feito aqui; frente independente do outro Coder. Estes specs FALHAM até o
  guard existir — estado = PENDENTE EXECUÇÃO, sem verde inventado.
- Sem Gate fake / Controller fake / rede: HTTP real + stub de método no `Channel::Whatsapp`
  (shape nativa `{'exists','jid'}`, fallback real do Baileys); `HTTParty`/WebMock NÃO usados;
  `allow(RubyLLM)` NÃO usado; `allow_any_instance_of` só no transporte com `rubocop:disable
  RSpec/AnyInstance` (mesmo padrão de `scope_b1_leftovers_spec.rb:59`).
- Prova de DB por contagem (`Contact`/`ContactInbox`) + leitura crua do dono (`reload.name`,
  `reload.custom_attributes`); nenhum exemplo deleta/mascara valor; `Contact`/`ContactInbox`
  criados nos positivos/controles são da própria conta de teste (isolamento do runner).
- Escopo de arquivos: só a nova spec + este doc + append changelog. Sem app/installer/helper,
  sem NotificationDeliverySpec, sem outros specs/shared/support, sem planos, sem PROJECT_STATE.

## 4. Validação real aqui (sem runtime)

- `ruby -c` 3.4.4 na nova spec → `Syntax OK`, EXIT 0.
- RuboCop check-only `env -i` + BUNDLE do launcher SÓ na nova spec → **0 ofensas**, EXIT 0.
- `git diff --no-index --check /dev/null <novaSpec>` → vazio (sem warning de whitespace).
- `git diff --check` (rastreado) → limpo. `git status --short` → só `??` pré-existentes + 2 novos.
- `df -h /tmp` → leitura (sem apagar). Nenhum rspec executado.
