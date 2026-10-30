# 39 — RF2 campos privados do contato (TASK_ID g0-rf2-private-spec) — MATRIZ NÃO EXECUTADA

Somente regressões RF2 (quebra de privacidade contato notas/custom attrs), sem app edit nem runtime.
Código RF2 será feito em frente independente após RF3; esta entrega usa contrato, não depende de helpers novos.
Arquivo novo único: `spec/connecta/scope_contact_fields_spec.rb` (10 exemplos, NÃO EXECUTADOS).
Fixture G0 existente + rotas nativas + tools/eventos reais. Dados sintéticos com sentinela de outra
situação/setor; sem duas etapas ativas do mesmo contato. Casos focados, sem explosão por permutação.

## 1. Contrato nativo (somente leitura nesta tarefa)

| Superfície | Fonte | Fato |
|---|---|---|
| Jbuilder do contato | `app/views/api/v1/models/_contact.json.jbuilder:11` | `custom_attributes` serializado no HTTP (`show/index/update/create` usam o partial). |
| GetContact Copilot | `enterprise/app/services/captain/tools/copilot/get_contact_service.rb:12` | `contact.to_llm_text` (formatter inclui attrs + notas). |
| Formatter LLM | `app/services/llm_formatter/contact_llm_formatter.rb:20` | `ContactLlmFormatter#format` monta attrs + todas as `notes` do contato. |
| Notas globais | `app/services/connecta/scope/contact_notes_hook.rb` | Contato vinculado: leitura 404, escrita 403 (bloqueio nativo já existente). |
| Visibilidade | `app/services/connecta/scope/contact_visibility.rb` | Vinculado só visível a quem vê alguma conversa dele; `guard!` leitura 404 / escrita 403. |
| Socket contato | `app/models/contact.rb` (`push_event_data`) | Inclui `custom_attributes` no payload de `contact.*`. |
| Socket mensagem | `app/models/message.rb` (`push_event_data` + `merge_sender_attributes`) | Embute `sender.push_event_data` (contato remetente) no evento. |
| Job broadcast | `app/jobs/action_cable_broadcast_job.rb` | Eventos de conversa relêem a conversa (`prepare_broadcast_data`); API pública `enqueued_jobs`/`ActiveJob::Arguments.deserialize`. |
| Matriz §10.1 | plano externo `2026-10-22-atendimento-dois-numeros-baileys.md:542-543` | Notas/atributos customizados de contato ocultos e bloqueados para usuários só escopados. |

## 2. Fixture e dados sintéticos

- Fixture G0 existente (`with connecta g0 scope fixture`): `conv_a`/`contact_a` (setor A, ator A `atender`),
  `contact_b`/`agent_b` (outro setor), `member_without_grant`, `manager_a`, `control_inbox`/`contact_control`
  (unmarked), admin nativo criado no exemplo (`role: :administrator`).
- Sentinelas sintéticas de outra situação/setor: attr global `rf2_global_secret=RF2-SENTINEL-ATTR-A`,
  nota global `RF2-SENTINEL-NOTE-A` (autora `agent_b`), nome público `RF2 Publico A`,
  telefone `+5511999990001`. Definição `custom_attribute_definitions` criada com
  `find_or_create_by!` (reuso entre exemplos, sem duplicar chave).
- Sem duas etapas ativas do mesmo contato (nenhum `ScopeB` terminal criado; só o vínculo A herdado do factory).

## 3. Matriz de casos (10 exemplos, todos NÃO EXECUTADOS)

| # | Superfície | Ator | Esperado |
|---|---|---|---|
| 1 | `GET contacts/:id` (A visível) | A | 200 + `payload.name == 'RF2 Publico A'` (nome público no retorno autorizado) + corpo sem `secret_attr_value/key` nem nota. |
| 2 | `GET contacts/:id` | B / membro | 404 + corpo sem segredos (negação geral NÃO mascarada como não-vazamento: o caso 1 prova o positivo). |
| 3 | `GET/POST contacts/:id/notes` | A | `GET` 404 sem sentinela; `POST` 403 + `Note.count` inalterado (escrita bloqueada sem alterar DB). |
| 4 | `PATCH contacts/:id` (attrs) | A | 403 + `raw custom_attributes` e `raw notes` exatamente iguais (leitura crua, sem getter mascarado). |
| 5 | `GetContact.execute` | A | Inclui nome público; sem attr secreto nem nota (include busca ampla anterior RF1 preservada no caso 6). |
| 6 | `SearchContacts.execute(name:)` | A | Inclui alvo visível sem segredos; sem LLM/rede/Gate fake. |
| 7 | `contact.updated` (autor admin) | escopo | A recebe, B/membro não; payload de A sem `secret_attr_value` (autor admin NÃO amplia). |
| 8 | `conversation.updated` (recarrega SenderContact) | escopo | A recebe sem attr/nota no payload; `message.sender_id == contact_a.id` como vínculo. |
| 9 | unmarked nativo | A | `GET contact_control` 200 nativo + raw attrs/notas intactos após leituras. |
| 10 | admin onde já era autorizado | admin | Sem permissão nova; raw attrs/notas permanecem (preserva nativo). |

Não ampliado: `AdminMarkedNotes`/rotas `Contact` que hoje já negam (nenhum exemplo concede acesso novo).

## 4. Limites honestos

- Código RF2 (ocultação real) NÃO feito aqui; frente independente após RF3. Estes specs FALHAM até o guard RF5
  existir — estado = PENDENTE EXECUÇÃO, sem verde inventado.
- Sem LLM/rede/Gate fake: listener + jobs nativos reais via `enqueued_jobs`; `allow(RubyLLM)` NÃO usado aqui
  (só onde o captain exige; estes casos de tools chamam `execute` direto).
- Prova de DB usa coluna crua (`pick`/`pluck`), nunca getter potencialmente mascarado; nenhum exemplo deleta/mascara valor.
- Escopo de arquivos: só a nova spec + este doc + append changelog. Sem app/installer/helper/code, sem outros
  specs/shared/support, sem RF3, sem planos, sem PROJECT_STATE.

## 5. Validação real aqui (sem runtime)

- `ruby -c` 3.4.4 na nova spec → `Syntax OK`, EXIT 0.
- RuboCop check-only `env -i` + BUNDLE do launcher SÓ na nova spec → **0 ofensas**, EXIT 0.
- `git diff --no-index --check /dev/null <novaSpec>` → vazio (sem warning de whitespace).
- `git diff --check` (rastreado) → limpo. `git status --short` → só `??` pré-existentes + nova spec.
- `df -h /tmp` → leitura (67%, sem apagar). Nenhum rspec executado.
