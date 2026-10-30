# T0.2 parte B2 — recuperação após timeout do lote (G0, 2026-10-22)

**Estado: PARCIAL.** O lote B2 foi interrompido por timeout de 1500 s (wrapper `20261022T170233-3111698`, `contract_ok: false`, sem relatório; `exec.log` e `output.txt` vazios). Esta recuperação não implementou nada: validou o que ficou no worktree e registrou o resultado. T0.2 segue ABERTO. G0 segue ABERTO.

Autorização: citação do briefing de recuperação (máquina local, worktree `chatwootnext-connecta-g0-prep`, banco `conecta_baileys_g0_test`, Postgres `127.0.0.1:55432`, Redis `127.0.0.1:56379`, dados sintéticos). Sem comando remoto, sem `down`, sem carga de schema, sem leitura de `.env`.

## 1. O que o lote interrompido deixou

Baseline do próprio lote: `08-baseline-sha256.txt` (17:05, antes das primeiras edições em 17:10). Para os dois arquivos existentes editados, o baseline é igual ao snapshot pós-B1 (`07-baseline-logs/sha256-depois.txt`), então as diferenças são do lote B2.

| Arquivo | Situação | Conteúdo |
|---|---|---|
| `app/services/connecta/scope/installer.rb` | editado (936 → 3225 bytes) | instala os hooks B2 e as guardas de criação, exportação, lote, transcrição e Captain; move o `rescue_from` de negação para o instalador (negação autenticada vira 404 ou 403) |
| `app/services/connecta/scope/conversation_http_hook.rb` | editado (2428 → 3068 bytes) | guarda de transcrição (`connecta_scope_transcript_guard!`, leitura auditada); remove o handler de negação movido para o instalador |
| `app/services/connecta/scope/{bulk,captain_tasks,contact,contact_filter_service,contact_notes,contact_subresource,contact_visibility,inbox,inbox_members,search,unread_count}_hook.rb` | novos (11) | hooks B2 |
| `spec/connecta/scope_related_http_spec.rb` | novo (28350 bytes) | 64 exemplos |

Dos 42 arquivos do snapshot pós-B1 (`07-baseline-logs/sha256-depois.txt`), 40 têm SHA256 igual; só os dois editados acima mudaram.

Git: nenhum arquivo rastreado alterado (`git diff --check` vazio). Todo o G0 segue **não rastreado** (`??`): `.context/`, `app/services/connecta/scope/`, `scripts/`, `spec/connecta/`, `spec/requests/connecta/`, `spec/support/connecta/`. Nenhum commit foi feito.

## 2. Validações desta recuperação

| # | Verificação | Resultado | Log |
|---|---|---|---|
| V1 | `ruby -c` (Ruby 3.4.4 do cache) nos 36 `.rb` do B2 e da B1 | `Syntax OK` em todos | — |
| V2 | `scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_related_http_spec.rb` sem o Ruby 3.4.4 no PATH | exit 1; abortado antes de qualquer comando (`falta: Ruby 3.4.4 (.ruby-version) no PATH`). Falha de ambiente, não de código | `08-logs/run-1-scope-related-http.log` |
| V3 | mesmo comando com `PATH=<toolchain 3.4.4>/bin:$PATH`, `timeout 180` | exit 0; **64 exemplos, 0 falhas**; 1 min 04 s | `08-logs/run-2-scope-related-http.log` |
| V4 | regressão combinada: `scope_policy_query`, `scope_http_filter`, `scope_related_http`, `route_inventory`, `agent_bot_delivery`, `attachment_access` | exit 0; **160 exemplos, 0 falhas**; 2 min 50 s (limite 180 s) | `08-logs/run-3-combinada.log` |
| V5 | RuboCop nos 14 arquivos Ruby do B2 (`env -i`, Ruby 3.4.4, `BUNDLE_*` do launcher) | `14 files inspected, no offenses detected`, exit 0 | `08-logs/rubocop-b2.log` |
| V6 | `git diff --check` (arquivos rastreados) | sem saída, exit 0 (não há rastreado alterado) | — |
| V7 | `git diff --no-index --check /dev/null <arquivo>` nos 14 arquivos B2 | sem saída; auto-teste com espaço no fim da linha detectou o erro, então a verificação é válida | `08-logs/diff-check-novos.log` |
| V8 | SHA256 de 40 arquivos antes (`08-logs/sha256-antes-recuperacao.txt`) e depois de V2–V7 | 40 OK, nenhuma alteração pela recuperação | `08-logs/sha256-depois-recuperacao.txt` |

Contagem: 160 = 64 (B2) + 96 anteriores. Contagem estática (`^\s*it`): `scope_policy_query` 30, `scope_http_filter` 34, `scope_related_http` 64, `route_inventory` 3, `agent_bot_delivery` 17, `attachment_access` 12, total 160, batendo com a execução. O "32" de `scope_http_filter_spec.rb` em `PROJECT_STATE.md` estava desatualizado; corrigido para 34.

Tentativas com falha de ferramenta, sem efeito no código:
- `bundle exec rubocop` com o PATH do mise: `mise ERROR No version is set for shim: rubocop`.
- Com o PATH do toolchain e sem as variáveis do launcher: `bundler: command not found: rubocop` (exit 127).
- Resolvido com `env -i` e `BUNDLE_GEMFILE`, `BUNDLE_PATH`, `BUNDLE_FROZEN` iguais aos do launcher (`scripts/connecta/g0_test_env.sh:47-49`). Armadilha registrada em `gotchas.md`.

Processos: nenhum `rspec` ou launcher residual. O PID do wrapper (3111761) não existe mais. Há um puma de outro projeto (`participa_cidadao`), não tocado.

## 3. Cobertura por área (lista do briefing de recuperação)

Legenda: **Provado** = exemplo verde nesta execução. **Negação nativa** = o exemplo confirma que a autorização nativa nega, sem hook próprio. **Lacuna** = sem exemplo ou sem código. Linhas são de `spec/connecta/scope_related_http_spec.rb`.

| Área | Implementação | Provado nesta execução | Lacunas |
|---|---|---|---|
| Contagem não lida | `unread_count_hook.rb` (prepend em `Conversations::UnreadCounts::Counter`) | **Provado**, 8 exemplos (L53–L115): agentes A e B, etiquetas e equipes, gestor, membro sem grant, admin nominal, grant revogado, 401 sem token | Só com a flag `conversation_unread_counts` ligada (padrão: desligada); com a flag desligada não há prova nesta spec |
| Busca global | `search_hook.rb` (`SearchService`) | **Provado**, 6 exemplos (L123–L164): conversa, mensagem e contato por A; B negado; admin nominal sem resultado de inbox marcada; controle | — |
| Contatos, notas e atributos | `contact_hook.rb`, `contact_visibility.rb`, `contact_subresource_hook.rb`, `contact_notes_hook.rb`, `contact_filter_service_hook.rb` | **Provado**, 15 exemplos (L175–L298): leitura, listagem, filtro, conversas do contato, notas (leitura 404, escrita 403), gestor sem alterar o global, exclusão e atributos negados, exportação negada | Criação de contato e atributos customizados de contato: sem exemplo |
| Ações em lote | `bulk_hook.rb` | **Provado**, 6 exemplos (L311–L357): status, mistura A/B sem sucesso parcial, gestor 403, atribuição, controle, exclusão de contato vinculado 403 | Lotes além de conversa (status, atribuição) e de exclusão de contato: sem exemplo |
| Inbox física: QR, sessão, status, verificação, edição, membros | `inbox_hook.rb`, `inbox_members_hook.rb`, guarda de criação no instalador | **Provado**, 9 exemplos (L368–L430): agente e gestor negados sem chamada ao transporte; admin nominal inicia pareamento (1 chamada ao stub); controle nativo recebe 422 | Caso positivo do admin só no pareamento; demais ações do admin sem caso positivo |
| Equipes e usuários | sem hook próprio | **Negação nativa**, 2 exemplos (L441, L454) | Escopo de equipe além da contagem não lida: sem exemplo |
| Relatórios, exportação e transcrição | `installer.rb` (exportação de contatos), `conversation_http_hook.rb` (transcrição) | Exportação de contatos: **provado** (L288, L298, dentro de contatos). Transcrição: **provado**, 4 exemplos (L490–L516), admin nominal com leitura auditada. Relatório agregado: **negação nativa** (L463) | Relatório ou exportação com admin nominal positivo; exportações além de contatos |
| Integrações (webhook e hook) | sem hook próprio | **Negação nativa**, 2 exemplos (L470, L478) | Caso positivo do admin; integração com guarda própria |
| Agendadas e recorrentes | guarda genérica em `conversation_http_hook.rb` | **Provado**, 5 exemplos (L524–L560): leitura negada para B, agendamento negado para gestor e B, atributos da própria conversa com grant | Agente com grant listando ou agendando na própria conversa: sem caso positivo |
| Chat interno e Captain | `captain_tasks_hook.rb` (só `captain/tasks`) | **Provado** para `captain/tasks`, 5 exemplos (L572–L600): B negado sem chamar o serviço de IA, grant, gestor, admin auditado, controle | Chat interno: sem hook nem exemplo. Demais rotas Captain: sem hook nem exemplo |
| Transversal: grant e epoch | `UserGrant`, `UserAuthEpoch` | **Provado**, 1 exemplo (L608) | — |

Soma: 8 + 6 + 15 + 6 + 9 + 2 + 3 + 4 + 5 + 5 + 1 = 64.

Lacunas herdadas da B1 (`07-scope-http-filter.md`, seção 6) continuam sem exemplo individual: `scheduled_messages` (GET, update, destroy), `reactions`, `attachments#update`, `direct_uploads`, `recurring_scheduled_messages`.

## 4. Fora de B2 (não iniciado)

Socket, download de anexos, notificações, transferência legada (T0.3), barreira (T0.7) e exportação de conversa. A B3 cobre esses itens. Nada disso foi tocado.

## 5. Riscos

- A regressão combinada levou 170 s de um limite de 180 s. O próximo acréscimo de specs deve estourar o limite. Opções: dividir em dois lotes (B1/T0.4/T0.5 e B2) ou elevar o limite do launcher. Recomendação: dividir.
- Nada foi commitado. O G0 inteiro está não rastreado no worktree `feat/connecta-g0-prep`.
- A prova de "transporte não chamado" usa o stub de pareamento. Não prova o Baileys real.
- Nenhuma decisão técnica rotineira ficou pendente.

## 6. Fontes

- `/home/thanos/.local/state/claude-coder/20261022T170233-3111698/result.json` (status, timeout), `exec.log` e `output.txt` (vazios). O briefing anterior não foi relido.
- `08-baseline-sha256.txt`, `08-baseline-git-status-antes.txt`, `07-baseline-logs/sha256-depois.txt`, `07-scope-http-filter.md`.
