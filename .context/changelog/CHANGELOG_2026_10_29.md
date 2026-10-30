# Changelog — 2026-10-29

## Consolidação de produção — F1

- Criada a branch final local a partir de EA (`ea9153f2`); preparada a integração da linha original G0 (`beaf180d`, 15 commits) por merge sem reescrever OIDs. A primeira tentativa de commit foi bloqueada pelo hook (histórico abaixo).
- Seis arquivos com dez hunks de conflito: traduções PT-BR, modal de vínculo WhatsApp, store de conversas, anotação do model Conversation, handler de conexão Baileys e schema.
- Mantidos os 5 CORE e os arquivos de infra de EA, além da precedência de URL do gateway por conta. QR local combinado com recursos de produção; revogação de escopo combinada com remoção de conversas de EA.
- Schema unido manualmente, preservando tabelas/índices de EA e adições locais. Nenhum banco acessado; regeneração fica para F5.
- Ledger por hunk: `/home/thanos/backups/consolidacao-20261029/ledger/conflitos-fork.tsv`. Validações e logs: `/home/thanos/backups/consolidacao-20261029/p1/fork/`.
- Validação: 27 verificações de integridade, 18 casos isolados do handler, 14 de interface/cache, 154 checagens de sintaxe e compilação do script/template do modal Vue sem erros. Não equivale a RSpec, Vitest, renderização Vue nem homologação funcional da integração.
- Commit normal tentou executar o hook: ESLint passou e aplicou formatação; RuboCop bloqueou com 27 ocorrências em 178 arquivos. Log em `p1/fork/f1-commit-attempt.log` no diretório externo de evidências. Não houve desativação, alteração de hook/configuração Git ou uso de `--no-verify`.
- Ao fim da primeira tentativa, F1 permaneceu bloqueado no commit. F2 não iniciado e depende de novo despacho; sem push, PR, deploy ou alteração dos originais A–E.

## Continuação autorizada de F1 — correção mínima do lint

- `.rubocop.yml` exclui somente `.context/evidence/**/*`: cópias históricas são documentos, não fontes executáveis. Nenhuma cópia foi editada/apagada; o hook já tinha `--force-exclusion` e ficou intacto. Os mesmos 152 arquivos ativos continuam inspecionados, sem ocorrências.
- Extraídos apenas `DashboardController#connecta_config` e `ConnectaScopesController#can_transfer?`, preservando os resultados e a ordem das consultas; os limites de métricas e regras ativas não mudaram. Formatação de dois comentários de índice e remoção de um disable redundante, sem alteração da lógica de ativação/locks.
- 199 verificações isoladas comprovam equivalência dos controllers e AST inalterada nos ajustes de comentários. As seis autoformatações da primeira tentativa também preservam AST de JavaScript e render Vue.
- Racional, diff e resultados em `p1/fork/f1-lint-fix.diff`, `f1-continuation-lint-scope.json`, `f1-lint-equivalence.log` e `f1-autofix-review.json` no diretório externo de evidências. Hunks adicionais documentados no ledger fork.
- Integração local por commit de merge normal, sem rebase, alteração de autoria/histórico, bypass de hook, push, PR ou deploy. Aceite final e OID no relatório externo `REPORT_F1_CONCLUIDO.md`. F2 não iniciado.

## Histórico importado do snapshot C

# Changelog 2026-10-29

## Micro passo 1 — rollback 404 da criação resolvido (código + regressão G0, NÃO PUBLICADO)
- Raiz (provada): `Connecta::Runtime::ReceptionScopeCreator.call` (`app/services/connecta/runtime/reception_scope_creator.rb:19` antigo) usava `find_or_create_by!(conversation_id:)`. Com o callback de recepção ativo (publicado em 28/10 via `Conversation.after_create`, `runtime/installer.rb:25`), a SEGUNDA conversa para o mesmo par (inbox, contato) — cenário do POST real `/api/v1/accounts/1/conversations` (inbox 3, contato 2) — fazia o INSERT violar o índice parcial `(inbox_id, contact_id) WHERE state IN (reception, active, transferring, pending_activation, activation_stuck)` por causa do escopo ativo da primeira conversa. O `rescue RecordNotUnique → find_by!(conversation_id: novo)` do próprio Rails (`create_or_find_by!`) não encontrava nada (conflito é por par, não por conversa) e levantava `ActiveRecord::RecordNotFound` com a condição `conversation_id=X AND conversation_id=X` duplicada → rollback da transação do controller → `handle_with_exception` renderiza 404 "Resource could not be found". Lookups de inbox/contato/contact_inbox passaram (não são a causa).
- Correção mínima (sem pular escopo, sem engolir erro de integridade, sem tocar gate/fencing/policy): idempotência explícita por `conversation_id` (retorna existente), senão na mesma transação aposenta escopos não-terminais anteriores do par (`transferred_out` via `update_all` indexado, mesma técnica do transfer local) e `create!` o escopo `reception`/`case_version 0`. Divisão em `retire_previous_open_scope!` + `create_reception_scope!` para manter RuboCop limpo.
- Regressão request real G0 `spec/connecta/runtime_reception_create_spec.rb` (NOVA, 6 exemplos): cria via POST com callback runtime ativo; segunda conversa mesmo contato comita 200 + escopo reception (anterior vira `transferred_out`, índices únicos preservados); idempotência do callback; conversa nasce sem mensagem de saída (sem envio antes de ativação); 10 criações sequenciais só última não-terminal; `source_id` cross-account 401 sem criar; inbox não marcada sem escopo/sem erro.
- Before/after (variante isolada em /tmp, sem descartar o fix): código HEAD (find_or_create) = 4 falhas; código corrigido = 6 exemplos, 0 falhas.
- Correlatas verdes no alvo G0 exato (`127.0.0.1:55432/conecta_baileys_g0_test` + Redis `127.0.0.1:56379`): `runtime_reception_scope` 4/0, `scope_http_filter` 38/0, `scope_policy_query` 46/0, `outbound_dispatch` 10/0. RuboCop nos 2 Ruby sem ofensas; `git diff --check` limpo.
- Limites: correção pronta p/ juiz, NÃO implantada (runtime 3006 segue imagem `272134b0…` com o bug; POST real ainda retorna 404 até novo deploy). Admissão por setor/popup, primeiro envio e conversa 5/parks seguem pendentes (próximos passos).

## Micro passo 1b — "Abrir existente" (supersede: SEM aposentadoria, NÃO PUBLICADO)
- Decisão funcional do usuário: contato com atendimento aberto → reutilizar o atual autorizado ("Abrir existente (Recomendado)"); sem acesso → bloquear sem encerrar/transferir implicitamente. A aposentadoria automática do passo anterior (`update_all transferred_out`) foi REMOVIDA — nunca publicada, e o briefing atual a rejeita como entrega (quebraria transfer/fence/session/outbox de outro atendimento).
- Raiz 404 mantida e provada (passo 1): `find_or_create_by!(conversation_id:)` no `ReceptionScopeCreator` viola o índice parcial `(inbox_id, contact_id)` quando o par já tem escopo não-terminal; o fallback `find_by!(conversation_id: novo)` não acha nada → `RecordNotFound` com condição duplicada → rollback → 404.
- Solução: `Connecta::Scope::ConversationReuse` (NOVO `app/services/connecta/scope/conversation_reuse.rb`) + `BuilderInterceptor` prepended no `ConversationBuilder` via `Installer.install_conversations!` (só teste G0). Com contact_inbox resolvido pelos before_actions nativos (conta/inbox/contact + inbox `show?`), toma o MESMO advisory lock por par do `LocalTransaction.lock!` e: (a) par sem escopo não-terminal → `super` (cria nova + callback reception idempotente por conversa, `create!` direto sem `find_or_create`); (b) par com atendimento autorizado → retorna a conversa existente (sem nova Conversation/scope, sem tocar escopo alheio, sem criar mensagem); (c) existente sem leitura → `Denied :forbidden` 403 genérico sem ID/dados, nada criado; (d) reuso com mensagem sem `write?` → 403 antes de qualquer criação (envio segue dispatch guard). Inbox não marcada: `nil`, fluxo nativo. `ReceptionScopeCreator` volta a `create!` idempotente por conversa (sem retirement).
- Por que não `prepend_before_action`: o reuso roda DEPOIS dos before_actions nativos (precisa de `Current.account` e `@contact_inbox` — ambos nil no prepend, o que dava 500 no diagnóstico). O interceptor no builder herda a ordem nativa correta sem reimplementar autenticação/autorização.
- Regressões: `spec/connecta/runtime_reception_create_spec.rb` (8 exemplos, reescrita p/ reuso): cria+reutiliza autorizado (sem nova conversa, escopo intacto), outro-setor-sem-acesso 403 sem vazar/criar, mensagem-sem-escrita 403 sem mensagem, idempotência do callback, nasce sem envio, 10 sequenciais reutilizam a 1ª, cross-account 401, inbox não marcada nativa. `spec/connecta/scope_http_filter_spec.rb` (39 exemplos): bloco criação atualizado — cria com contato fresco, reuso via inbox_id/source_id devolve display existente, outro-setor 403.
- Validação alvo G0 exato: reuso 8/0, filtro 39/0, policy 46/0, outbound 10/0, reception 4/0. RuboCop 6 arquivos limpo; `git diff --check` limpo. Nenhum dado real; sem deploy.
- Limites: NÃO PUBLICADO (3006 segue imagem `272134b0…` com 404). Admissão por setor (auto/popup), primeiro envio e parks da conversa 5 seguem pendentes.

## Consolidação de produção — F2 (snapshot C, WIP incluído)

- Merge normal de `snap/C-wt` (`e36b9f82`) sobre F1 aceito (`eacee00fb`): 62 SRC, incluindo os 23 arquivos originalmente não rastreados de C. Sem uso do worktree C vivo como fonte.
- NativeAdmin, manual admission, ConversationReuse, ReceptionScopeCreator working tree, assinatura Baileys negrito-itálico e specs incorporados. WIP continua WIP; os relatos antigos acima são históricos, não validações desta branch.
- Seis hunks em cinco arquivos: união documental; helper de permissão F1 com NativeAdmin C; composição nativa de EA com guard C; distinção de parked pré-admissão/transferência. Ledger F2 acrescentado, sem substituir registros F1.
- Ajustes mínimos de lint: bindings sem uso removidos no UI WIP, declarações reordenadas, argumento Ruby não usado renomeado e delimitadores de regex equivalentes. Nenhum limite/guard/hook relaxado; cópias históricas não editadas.
- Limitações reais herdadas: seletor ainda não montado no template; anexos adicionais `followUpFiles` não propagados pelo novo caminho de admissão. A sequência EA é mantida no caminho nativo. Não completar esses comportamentos nesta integração de snapshot.
- Disposição provisória por hash/diff dos 62 paths e validações focadas em `/home/thanos/backups/consolidacao-20261029/p1/fork/f2/`. Sem RSpec/DB/container, sem patch F5/HMAC de outros agentes e sem iniciar F3/F4/F5. Sem push, PR ou deploy.
- Validação isolada F2: 68 verificações Ruby de NativeAdmin/helper/assinatura/equivalência, 34 verificações JS dos hunks (incluindo seis compilações Vue) e 37 checagens de sintaxe, sem executar specs de integração. Dois avisos `vue/no-root-v-if` herdados são registrados no relatório, sem desabilitar regra. O commit normal executa o hook completo das fontes staged.

## Consolidação de produção — F3 (E por comparação, sem reaplicar)

- Comparados os nove SRC de E (`0442d470`) com C (`e36b9f82`) e a integração F2 (`bb4dcce7`). Nove diffs E→C e provas auxiliares base→E/C→F2 em `/home/thanos/backups/consolidacao-20261029/ledger/e-vs-c/f3-0442d470-e36b9f82/`, sem sobrescrever provas.
- Dezessete hunks de E revisados. Editor.vue e ReplyBottomPanel.vue são blobs idênticos em E/C (DUPLICADO). Seis arquivos de código/spec são SUPERADOS por C: guards e toggle preservados, formato Baileys evoluído para `*_Nome_*:`, legado normalizado e cobertura ampliada. Nenhum hunk de código E faltante nem port funcional necessário.
- O changelog E trouxe detalhes históricos exclusivos; foram preservados com atribuição e limites em `CHANGELOG_2026_10_28.md`, seção “Histórico exclusivo de E / S.1 básica”. Contagens antigas não são medições desta etapa nem foram artificialmente reconciliadas.
- Disposição F3: um INCLUIDO documental, dois DUPLICADO e seis SUPERADO. Tabela por path e justificativa em `p1/fork/f3/disposicao-E.tsv`; mapa de todos os hunks, testes focados sem banco e aceite no mesmo diretório externo.
- Nenhum E inteiro reaplicado, nenhuma alteração de código/spec, nenhum teste novo de F4/HMAC/realtime adicionado. Sem Vitest amplo, RSpec, banco, container, push, PR ou deploy.

## Consolidação de produção — F4 frontend (regressão Vitest)

- Suite completa: 4802 passaram, 23 skipped, 5 falharam.
- 3 falhas em `TransferAction.spec.js` são **preexistentes** em produção (mesma mensagem em EA); não corrigidas nesta entrega.
- Corrigido: `ConnectaScopeRevoked` — a revogação alvo-específica (conversa) não pode apagar outras conversas da mesma inbox; o contrato de `acl.revoked` exige remoção cirúrgica (`actionCable.js`).
- Corrigido: `TransferActionSummary.spec` — seletor pegava o campo de busca do ComboBox; agora `input.form-input`. Componente estava correto.
- Pós-correção focada: 3/3 revogação, 1/1 resumo, 281/281 conversas e tempo real.
- F4 backend (Ruby): limitação registrada — 373 gems do lock ausentes no toolchain; rubocop e RSpec não executados. Sintaxe 164/164 válida.
- Commit: `853bbbf59`. Relatório: `p1/fork/f4/frontend-resultado.md`.
