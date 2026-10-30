# 50 — RF2 Copilot mostra contato (TASK_ID g0-rf2-copilot-code) — CÓDIGO ESCRITO, RUNTIME PENDENTE

Somente RF2 Copilot (outra frente cobre HTTP; socket RF5 fica para frente própria).
Código test-only; sem ativar em produção; nenhum banco novo.

## 1. Arquivos (somente ownership autorizado)

- `app/services/connecta/scope/contact_data_projection.rb` (editado): nova API
  `ContactDataProjection.llm_text(contact, user)`. Sem restrição segue nativo
  (`contact.to_llm_text`); restrito (`restricted_contact?` real: vinculado +
  sem admin nominal) monta texto com `Contact ID` + campos públicos nativos
  (`Name/Email/Phone/Location/Country Code`), sem notas globais nem custom
  attributes. Contrato nativo lido: `app/services/llm_formatter/contact_llm_formatter.rb:20`.
  Sem tocar core/model/getters; sem apagar/mudar dados; sem regex sobre texto.
- `app/services/connecta/scope/copilot_tool_hook.rb` (editado): no search RF1
  existente, trocada só a formatação de cada resultado pela API com `@user`
  (`ContactDataProjection.llm_text`), preservando filtro individual, limit 100
  e filters nativos. No `get_contact`, mantido o guard de conta/visibilidade
  (`connecta_scope_copilot_contact_denied?`) e formatado pela mesma API com
  `@user` (nunca `Current.user`); `nil` quando fora do `visible_scope`
  (guard acima decide negar). Guards de `GetConversation`/`SearchConversation`
  inalterados; `connecta_scope_copilot_tool_denied?` sem caller preservado
  (outra frente decide remover ou ligar).

## 2. AC (runtime pendente, sem RF validada)

- AC1: search amplo continua filtrando cada resultado RF1 e nunca formata
  contato alheio (filtro individual + `visible_scope` preservados).
- AC2: get/search de contato visível não retornam notas globais/attrs para
  escopado (projeção restrita sem notas/custom attributes).
- AC3: contatos nativos unmarked preservados (`to_llm_text` nativo) e nenhum
  dado armazenado alterado (só formatação de resposta).

## 3. Validação real aqui (sem runtime)

- `git status --short` só `??` pré-existentes (nenhum rastreado modificado).
- `df -h /tmp` leitura 67% (sem apagar).
- `ruby -c` 3.4.4 `Syntax OK` nos 2 arquivos tocados.
- RuboCop `env -i` + BUNDLE do launcher só nos 2 arquivos → **0 ofensas**
  (com disable local `Metrics/CyclomaticComplexity` no novo `get_contact`,
  justificativa no método; padrão do arquivo já usa disables locais).
- Whitespace `git diff --no-index --check /dev/null` vazio nos 2;
  `git diff --check` limpo.
- Nenhum spec/rspec/Rails/build executado; runtime só após implementação completa.

## 4. Limites honestos e APIs finais

- Código escrito e NÃO executado; sem verde funcional inventado; RF2 NÃO validada.
- APIs finais: `ContactDataProjection.llm_text(contact, user)`,
  `ContactDataProjection.restricted_contact?(contact, user)` (inalterada),
  `ContactDataProjection.redact_contact(payload)` (inalterada, HTTP).
- Limites: só formatação de resposta das tools de contato; socket RF5, HTTP RF2
  já escrito (evidência 42) e demais RFs ficam para frentes próprias.
