# 42 — RF2 HTTP mostra contato (TASK_ID g0-rf2-http-integrate) — CÓDIGO ESCRITO, RUNTIME PENDENTE

Somente RF2 HTTP (outra frente cobre Copilot/socket). Guard RF3 create e escrita de contato NÃO enfraquecidos.
Integração via `after_action` registrado so no prepend (base nativa NÃO editada); apps nativos não editados.

## 1. Arquivos (somente ownership autorizado)

- `app/services/connecta/scope/contact_hook.rb` (editado, test-only): `self.prepended` registra
  `after_action :connecta_scope_redact_contact_response!, only: %i[index show search active filter]`.
  Apos o render nativo, redige SOMENTE DTOs de contato marcado para leitor so escopado:
  remove `custom_attributes`/`notes` do JSON ja renderizado, mantendo nome/telefone/id.
  Unmarked segue nativo; admin nominal segue nativo; negados (403 escrita, 404 leitura, NotesHook) intactos.
  Nunca toca Conversation/protocolo embutido: atua so por `@contacts`/`@contact` ja carregados na acao
  (estrutura nativa show=payload unico, index/search/active/filter=payload lista; create RF3 usa
  `payload.contact` + `payload.contact_inbox` e NAO passa pelo `only`), sem recursao cega por chave.
  `create` publico + guards RF3 (`connecta_scope_contact_create_guard!`, escrita, export) inalterados.
  Chaves do DTO lidas como string (`entry['id']`), conforme JSON renderizado; `JSON::ParserError` retorna nil.
- `app/services/connecta/scope/contact_data_projection.rb` (lido, NAO editado): `redact_contact(payload)` e
  `restricted_contact?(contact, user)` (`ContactVisibility.linked?` + `!Projection#admin?` real).
- `spec/connecta/scope_contact_fields_spec.rb` (outro Coder, NAO executado aqui): casos HTTP 1–4, 9–10 cobrem
  AC1–AC3; Copilot/socket (casos 5–8) ficam para a proxima frente RF2.

## 2. Contrato nativo lido (somente leitura)

| Superfície | Fonte |
|---|---|
| Acoes/leitura | `contacts_controller.rb:19-32,53-72` (`index/search/active/filter/show`) + `fetch_contacts`/`fetch_contacts_with_has_more` (:145-172) |
| DTO contato | `app/views/api/v1/models/_contact.json.jbuilder:11` (`custom_attributes` no parcial) |
| DTOs contato por acao | `index/show/search/active/filter/update/avatar/destroy_custom_attributes` usam parcial `contact`; `create` usa `payload.contact` + `payload.contact_inbox`; `conversations/attachments/group_members/contactable_inboxes/notes/*` NÃO usam parcial `contact` |
| Guards preservados | `contact_hook.rb:78-134` (fetch/write/export RF3), `contact_notes_hook.rb` (notas 404/403), `contact_visibility.rb` (linked/guard) |

## 3. AC (runtime pendente, sem RF validada)

- AC1: apos implementacao completa + runtime, `GET contacts/:id` e listas de contato visível marcado devem
  ocultar attrs globais/notas mantendo nome/telefone/id; unmarked nativo. Prova: spec 39 casos 1, 9 (outro Coder).
- AC2: `create` RF3 e guard de escrita de contato NÃO enfraquecidos (guards intactos, `only` exclui create/update).
- AC3: sem remover dados de outros recursos nem mudar persistência (sem getter mask, sem `ContactInbox`/Conversation).

## 4. Validacao real aqui (sem runtime)

- `ruby -c` 3.4.4 `Syntax OK` nos 2 arquivos tocados/lidos (`contact_hook.rb`, `contact_data_projection.rb`).
- RuboCop `env -i` + BUNDLE do launcher nos mesmos 2 → **0 ofensas**.
- Whitespace: `git diff --no-index --check /dev/null <arquivo>` vazio nos 2 (exit 1 = ha diff contra /dev/null, so saida conta).
- `git diff --check` limpo; `git status --short` so `??` pré-existentes; `df -h /tmp` leitura 67% (sem apagar).
- Nenhum spec/rspec/Rails/build executado; runtime pendente apos implementacao completa (Bloco D).

## 5. Limites honestos

- Codigo escrito e NÃO executado; sem verde funcional inventado; RF2 NÃO validada.
- Installer NÃO editado (prepend registra o callback; sem rota nova).
- NotesHook, fetch/write/export guards, Projection/admin e persistência inalterados.
