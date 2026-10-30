# 23 — team_id T0.2-c6 parte a: guarda 422 (IMPLEMENTADO / NÃO VALIDADO)

- Data (UTC): 2026-10-24.
- TASK_ID: g0-t02-c6a.
- Natureza: **registro documental**. Nenhum código foi alterado e nenhum teste/lint/build foi executado nesta tarefa.
- Status da seção team_id: **IMPLEMENTADO (código) / NÃO VALIDADO (funcional)**.
- Base de leitura (somente estes 3 arquivos estáveis; outros hooks/installer/spec em mutação por outras frentes **não** foram lidos):
  - `app/services/connecta/scope/denied.rb` (16 linhas)
  - `app/services/connecta/scope/conversation_http_hook.rb` (83 linhas)
  - `app/services/connecta/scope/bulk_hook.rb` (49 linhas)
- Checagem de espaço (somente leitura, sem apagar): `df -h /tmp` → `tmpfs 7.6G, 5.1G usados, 2.6G livres, 67%` em 2026-10-24.
- Antecedente: código team_id já escrito segundo log da tarefa anterior; aqui só se documenta. O `ruby -c` citado para esse código rodou em Ruby 4.0.7, mas a versão do projeto é 3.4.4 — **limitação real até checagem correta**; nada foi reexecutado aqui.

## 1. Comportamento pretendido (o que a tarefa parcial queria)

- `team_id` proibido em inbox marcada (T0.2-c6, parte a; matriz 10.1 citada nos comentários).
- Guarda roda **após** autorização de escrita, para não ampliar acesso nem revelar existência: fora do escopo continua 404/403 pelo caminho nativo.
- Presença do parâmetro (inclusive `null`/mesmo valor, inclusive aninhado) é tentativa e vira 422; nada é gravado.
- Em lote: com escrita autorizada em todo alvo marcado, presença do parâmetro vira 422 antes de enfileirar; lote misto não aplica nada.
- Contato excluído fica para outra entrega (ver §6).

## 2. Código observado (o que os 3 arquivos dizem; não é prova funcional)

### 2.1 `denied.rb:1-16`

- `Connecta::Scope::Denied < StandardError` (`:3`), `attr_reader :status` (`:10`), `initialize(status)` com `MESSAGES.fetch(status)` (`:12-15`).
- `MESSAGES` (`:4-8`): `not_found: 'Resource could not be found'`, `forbidden: 'You are not authorized to do this action'`, `unprocessable_entity: 'Team assignment is not allowed in this inbox'` (`:7`).
- Comentário (`:1-2`): negação HTTP do spike G0 para usuário autenticado — 404 na leitura, 403 na escrita e na criação, 422 em `team_id` proibido; renderizada só pelos controllers do spike.

### 2.2 `conversation_http_hook.rb:20-49` — fluxo guard422 após autorização

- `connecta_scope_write_guard!` (`:20-25`): retorna sem fazer nada se `request.get?`, `action_name == 'transcript'`, `@conversation.nil?` ou inbox **não** marcada por `Connecta::Scope::Projection.marked?(@conversation.inbox_id)` (`:21`). Com escrita autorizada por `Connecta::Scope::Gate.new(Current.user).write?(@conversation, access_path: connecta_scope_access_path)` (`:22`), desvia para `connecta_scope_team_guard!`; sem escrita autorizada, `raise Denied, :forbidden` (`:24`).
- `connecta_scope_team_guard!` (`:30-34`): se `connecta_scope_team_param?`, cria auditoria `Connecta::Scope::AccessAudit.create!(user_id: Current.user.id, conversation_id: @conversation.id, surface: 'conversation', access_path: "#{connecta_scope_access_path}_team", decision: 'deny')` (`:31-32`) e levanta `raise Denied, :unprocessable_entity` (`:33`).
- `connecta_scope_team_param?` (`:36-38`): `connecta_scope_deep_key?(params.to_unsafe_h, 'team_id')` (`:37`).
- `connecta_scope_deep_key?` (`:40-49`): recursão em `Hash` (`k.to_s == key ||` desce em `v`, `:44`) e `Array` (desce em cada elemento, `:46`); senão `false` (`:48`). Ou seja, chave profunda: topo ou aninhada, qualquer valor inclusive `null`.
- Comentários (`:17-19,27-29`): só roda depois da escrita autorizada; fora do escopo continua 404/403 sem revelar existência; presença/anexos/Copilot e contato excluído não são tocados aqui.

### 2.3 `bulk_hook.rb:18-42` — lote

- `connecta_scope_bulk_conversations!` (`:18-26`): alvos = `Current.account.conversations.where(display_id: Array(params[:ids]), inbox_id: marked_inbox_ids)` (`:19`); `return if targets.none?` (`:20`). Exige leitura em todos (`gate.read?` com `access_path: 'bulk_conversation'`, senão `:not_found`, `:23`) e escrita em todos (`gate.write?`, senão `:forbidden`, `:24`); só então `raise Denied, :unprocessable_entity if connecta_scope_bulk_team_param?` (`:25`), antes de enfileirar.
- `connecta_scope_bulk_team_param?` (`:28-31`): `connecta_scope_bulk_deep_key?(payload['fields'], 'team_id') || connecta_scope_bulk_deep_key?(payload, 'team_id')` (`:30`), onde `payload = params.to_unsafe_h` (`:29`).
- `connecta_scope_bulk_deep_key?` (`:33-42`): mesma recursão Hash/Array de `:36-40`.
- Comentários (`:1-5`): prepend antes de enfileirar o job; um alvo sem leitura falha tudo (404), um sem escrita também (403); nada é enfileirado com sucesso parcial; lote misto não aplica nada.

## 3. Prova pendente (o que NÃO se afirma)

- **Atribuição e lote NÃO foram validados**: nenhum spec/request/lint/build foi executado nesta tarefa; não se afirma que atualizar, atribuir em massa ou negar `team_id` funciona na prática.
- `ruby -c` anterior em Ruby 4.0.7 não vale como checagem do projeto (3.4.4); checagem sintática correta pendente.
- Instalação dos prepends (quais controllers, ordem, Installer) **não** foi lida aqui — outra frente (Coder contact / Installer) a edita.
- Renderização HTTP de `Denied` (`:unprocessable_entity` → 422 real) não foi lida nem provada aqui.
- Auditoria do caminho de lote para `team_id` (sem `AccessAudit` próprio em `:25`, ao contrário do caminho unitário `:31-32`) é só o que o código mostra; efeito funcional pendente.

## 4. Abrangência real (limites do que o código cobre)

1. Só inbox marcada (`Projection.marked?` / `marked_inbox_ids`); fora dela, nativo.
2. Só usuário autenticado (`current_user`/`Current.user` exigidos; não autenticado segue para o 401 nativo — `conversation_http_hook.rb:6-13,53-55`, `bulk_hook.rb:10`).
3. Só escrita não-GET em conversa, exceto `transcript` (guarda própria de admin em `:65-73`) e exceto transferência legada (negada em `:75-78`).
4. Criação em inbox marcada é negação 403 separada (`:53-63`), antes de qualquer I/O; não passa pela guarda 422.
5. Leitura negada em inbox marcada vira 404 (`:7-13`); não revela existência.
6. Lote só tipo `Conversation` passa por leitura+escrita+422; tipo `Contact` tem guarda própria de vinculado (`:44-48`), sem 422 de `team_id` — e contato excluído segue pendente (§6).

## 5. Limites observados (sem inventar garantia)

1. `null`/mesmo valor contam como tentativa: qualquer presença da chave nega; o código não compara valor antigo/novo.
2. Chave profunda varre `params.to_unsafe_h` inteiro (unitário) e `fields`+payload (lote); colisão de nome em estrutura aninhada não relacionada negaria do mesmo jeito — sem prova de que isso é desejado/indesejado.
3. Auditoria `deny` com `access_path` sufixado `_team` existe no caminho unitário, mas não no caminho de lote para `team_id`.
4. `bulk_conversations!` retorna sem negar quando nenhum alvo está em inbox marcada (`:20`); lote misto com alvos marcados+desmarcados só valida os marcados aqui.
5. Sem `Current.user`, hook de anexo cai para nativo — fato da evidência 20, citado só para não confundir escopo; este documento não cobre anexos.

## 6. Contato excluído: PENDENTE (outra entrega)

- `bulk_contacts!` (`:44-48`) nega (`:forbidden`) ação em lote de contato (rótulo ou exclusão) quando há vinculado global (`ContactVisibility.linked_ids`); isto é o que o código diz.
- **Contato excluído (`contact.deleted` / exclusão unitária / janela de corrida) NÃO é objeto desta evidência** e continua pendente para outra entrega. Nada aqui afirma seu comportamento.

## 7. O que este documento afirma / não afirma

- Afirma: os 3 arquivos existem com o fluxo guard422 após autorização e a chave profunda acima (código lido em 2026-10-24).
- Não afirma: que atribuir `team_id` nega 422 na prática, que o lote valida corretamente, que a auditoria grava, que o 422 chega ao HTTP, nem que contato excluído está tratado. Tudo isso é **validação funcional pendente** (specs próprios, tarefa posterior, Ruby do projeto 3.4.4).

## 8. Links locais usados (existem nesta worktree)

- `app/services/connecta/scope/denied.rb`
- `app/services/connecta/scope/conversation_http_hook.rb`
- `app/services/connecta/scope/bulk_hook.rb`

## 9. T0.2-c6b (TASK_ID g0-t02-c6b): spec escrita e NÃO EXECUTADA + contato implementado

- Data (UTC): 2026-10-24. Natureza: **escrita de spec + registro documental**. Nenhum código app/installer alterado.
- Arquivo novo: `spec/connecta/scope_team_contact_spec.rb` (19 exemplos, **NÃO EXECUTADOS**).
  Parte request (`type: :request`): rotas reais reconhecidas por `recognize_path` antes das chamadas —
  `PATCH conversations/:id` → `conversations#update`, `POST conversations/:conversation_id/assignments` → `assignments#create`,
  `POST bulk_actions` → `bulk_actions#create` (fontes: `config/routes.rb:147-193`, `assignments_controller.rb:1-11`,
  `bulk_actions_controller.rb:3-14`) — para não confundir 404 de rota inexistente com 404/403 de ACL.
  team_id por ator autorizado (agent_a, grant `atender` no setor A) em update, assignments e lote: presença no topo,
  `null`, mesmo valor e aninhado (`conversation[team_id]`, `assignment[team_id]`, `fields[nested][team_id]`) esperam **422**
  com a mensagem de `denied.rb:7`, sem mudar `team` e (lote) sem enfileirar `BulkActionsJob`; lote misto
  marcado+desmarcado com `team_id` também espera 422 sem aplicar nada. Fora do escopo continua 404/403 pelo caminho
  nativo (PolicyHook/Gate), sem revelar nem ampliar acesso. Controle de inbox não marcada: update ignora `team_id`
  (nativo, sem 422), assignments atribui de verdade, lote enfileira nativo.
- Parte listener (`ActionCableListener`, sem stub de Gate/Projection/ContactVisibility): usa o caminho real
  `Contact#destroy` (com `ContactLifecycleHook#destroy` capturando `CONTACT_SNAPSHOT_KEY`) → `SocketHook` no
  `contact.deleted`. O spec apaga o `ContactInbox` antes do broadcast para reproduzir a janela de corrida
  (`contact_inboxes dependent: :destroy_async` em `contact.rb:62` + `after_destroy_commit :dispatch_destroy_event`
  em `:74` via `SyncDispatcher`). `contact_data` montado como o nativo (`push_event_data.merge(account_id:)`,
  `contact.rb:161-177,257-265`), sem PII no snapshot (só `contact_id/account_id/tokens`).
  Snapshot esperado = tokens de agent_a + manager_a (leitores via `ContactVisibility.visible_scope`), admins
  (nominal e nativo) fora — contrato `socket_hook.rb:68-73,130-143` e `contact_lifecycle_hook.rb:40-45`.
  Sem snapshot (contato sem vínculo marcado): segue nativo no stream `account_<id>`. Misto marcado+desmarcado usa
  snapshot, sem stream da conta. Destruição/broadcast locais com jobs stubados (`allow(dispatcher).to receive(:dispatch)`,
  `clear_enqueued_jobs`/`enqueued_jobs`), sem rede real (`a_request(:any, /.*/)` não feita). Gate nunca desligado.
- Arquivos de contato (código estável, só leitura): `app/services/connecta/scope/contact_lifecycle_hook.rb` (46 linhas:
  `destroy` captura snapshot de membros com `ContactVisibility.visible_scope`, limpa se `destroyed?` falso),
  `app/services/connecta/scope/socket_hook.rb:79-96,116-128` (snapshot consome e substitui tokens no `contact.deleted`;
  sem snapshot segue vínculo vivo/nativo; consumo impede cair no stream da conta).
- Validação feita aqui: `ruby -c` com a toolchain do projeto **3.4.4** → `Syntax OK`; `git diff --check` limpo;
  `git status --short`; `df -h /tmp` (67% usado). **Spec NÃO executada** (proibido pelo briefing); sem lint/build.
- Limites/pendências: funcional NÃO provado (nenhum exemplo rodou); auditoria `_team` só existe no caminho unitário,
  não no lote (`bulk_hook.rb:25` sem `AccessAudit`, ver §5.3); `DELETE contacts/:id` de vinculado é bloqueado antes
  pela autorização nativa (spec cobre só o caminho do listener, não o HTTP feliz de exclusão — impossível para
  vinculado); `destroy_async` real em ambiente de spec pode variar o timing da corrida — o spec força a exclusão do
  vínculo para determinismo; instalação dos prepends (`Installer`) apenas assumida via `install!` como nos demais
  specs G0.
