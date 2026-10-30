# T0.2-c10 · complementos da B2 (G0, 2026-10-23)

Escopo: lacunas da seção 3 de `08-recuperacao-b2.md` que pedem só exemplos. Spec nova: `spec/connecta/scope_b2_complements_spec.rb` (12 exemplos, 0 falhas na versão final). Nenhum código de app, hook, `installer.rb`, spec existente ou `scripts/connecta/*` foi alterado. Dados sintéticos, banco `conecta_baileys_g0_test`, sem stub de transporte (nenhum exemplo chega ao adaptador).

## 1. Lacuna → exemplo → resultado

| Lacuna (08 §3) | Exemplo (linha da spec) | Resultado |
|---|---|---|
| Contatos: criação por agente A, agente B e membro sem grant | criação por agente A, agente B e membro sem grant… (L30) | Provado: 200 para os três; resposta sem `"display_id"` (nenhuma conversa); nenhum registro `surface: conversation` na auditoria, ou seja, a criação não passa pelo Gate |
| Contatos: atributos customizados por A, B e membro | atributos de contato vinculado… (L43) | Provado: A recebe 403 (escrita em contato vinculado); B e membro sem grant recebem 404 (contato não visível); o valor segue `plano => basico` |
| Lote: etiquetas em conversas | agente A adiciona etiqueta… (L59) | Provado: A aplica a etiqueta às próprias conversas pelo job |
| Lote: mistura A/B com etiqueta | mistura de conversa de A e de B… pedida por B (L70) | Provado: B recebe 404; nada enfileirado; nenhuma etiqueta aplicada (sem sucesso parcial) |
| Admin: leitura da inbox (GET) | admin nominal lê a inbox marcada… (L92) | 200, sem `provider_config`. **Sem registro de auditoria** em `surface: inbox`: `show` não está em `NOMINAL_ACTIONS` (`inbox_hook.rb:4-5`); a leitura segue nativa por desenho. Caracterização, não vazamento |
| Admin: lista de membros | admin nominal lista os membros… (L100) | 200 com agente A e membro sem grant na lista; sem auditoria, porque `inbox_members_hook.rb:8` retorna em GET |
| Admin: atualização de configurações da inbox | administrador da conta com grant renomeia… (L108) | 200; nome gravado; auditoria `inbox_update` com `decision: allow`. Exige papel `administrator` (`inbox_policy.rb:45-47`), além do grant |
| Admin: atualização com papel de agente | ACHADO: admin nominal com papel de agente… (L117) | **ACHADO-1**: 401 do nativo, nome intacto, mas a auditoria grava `allow` em `inbox_update` (ver §2) |
| Admin: integrações (lista de webhooks) | webhooks: administrador da conta lista… (L126) | Administrador da conta: 200. Admin nominal com papel de agente: 401 do nativo (`webhook_policy.rb:2-3`). Não há hook: vale o papel nativo, não o grant |
| Admin: relatório v2 (resumo de agente) | relatório agregado de agente… (L134) | Administrador da conta: 200. Admin nominal com papel de agente: 401 do nativo (`summary_reports_controller.rb:29-31`, `authorize :report, :view?`) |
| Agendadas: agente com grant | agente A lista e agenda mensagem… (L144) | Provado: A lista (200) e cria mensagem pendente na própria conversa (+1 registro, conteúdo gravado) |
| Não lidas com a flag desligada | agentes A e B recebem 403… (L160) | Provado: 403 com `error` e sem `payload` para A e B. `unread_counts_controller.rb:2` e `:27` (`ensure_unread_counts_enabled`) barram antes do contador. Sem vazamento com a flag desligada |

Conclusão: todas as lacunas com exemplo estão cobertas. Nenhum dado de conversa da inbox marcada vazou nos exemplos.

## 2. ACHADO e caracterização

- **ACHADO-1 (auditoria incorreta, sem vazamento de dados).** Admin nominal com papel de agente faz `PATCH` na inbox marcada. O `InboxHook#fetch_inbox` (`inbox_hook.rb:9`, com o registro em `:21`, chamado antes do `check_authorization` do controller, `inboxes_controller.rb:3` e `:7`) grava `allow` em `inbox_update`. Depois, o nativo responde 401 (`InboxPolicy#update?` exige administrador). Resultado: o registro diz que a ação foi permitida, mas ela não ocorreu. Nome da inbox intacto. Não corrigido aqui.
- **Caracterização (decisão pendente).** Leitura da inbox (`show`) e lista de membros não geram registro de auditoria, por desenho (`inbox_hook.rb`: "Leitura da inbox (show, campanhas) segue nativa"). Se a leitura precisa de trilha, é decisão de produto.

## 3. Execuções

| Execução | Comando | Resultado |
|---|---|---|
| run-1 | runner com lock (`--spec --apply`) | exit 1, 12 exemplos, 1 falha. Causa: a spec enviava `inbox: { name }`; `inboxes_controller.rb:308-311` lê só parâmetros de topo e descarta o aninhado, então o 200 não mudou o nome. Corrigido na spec (`name` de topo), não no app. Log: `15-logs/run-1-b2-complementos.log` |
| run-2 | runner com lock | exit 0, 12 exemplos, 0 falhas. Antes da quebra de linha do RuboCop. Log: `15-logs/run-2-b2-complementos.log` |
| RuboCop (1ª) | `env -i` + `BUNDLE_*` do launcher | 1 ofensa: `Layout/LineLength` (151/150), L149. Corrigida; o log foi sobrescrito pela versão final |
| run-3 (final) | runner com lock | exit 0, 12 exemplos, 0 falhas. Log: `15-logs/run-3-b2-complementos.log` |
| RuboCop (final) | `env -i` + `BUNDLE_*` do launcher | exit 0, 1 arquivo, sem ofensas. Log: `15-logs/rubocop-b2-complementos.log` |

## 4. O que não foi coberto

- `POST contacts` com `inbox_id` da inbox marcada (criaria vínculo contato–inbox marcada). Não coberto nesta tarefa: passa por `ContactInboxBuilder` com `validate_baileys_phone: true` (`contacts_controller.rb:174-182`), que pode chegar ao transporte. Exige stub de transporte e decisão de escopo. Fica como pendência.
- Relatório com admin nominal positivo sem papel de administrador: não há caminho positivo; o nativo nega (§1).
- Unread com a flag ligada: já coberta na B2 (`scope_related_http_spec.rb`, L40–L115). Aqui só a flag desligada.

## 5. Pendências para decidir

1. ACHADO-1: corrigir a ordem (gravar `allow` só após o nativo) ou aceitar o registro atual.
2. Auditoria de leitura da inbox e da lista de membros: sim ou não.
3. Candidato a `gotchas.md` (fora do IN-SCOPE desta tarefa): `PATCH` de inbox lê parâmetros de topo; `inbox: {...}` é descartado sem erro (200).
