# Changelog 2026-10-23

## Added

- `spec/connecta/captain_scope_spec.rb` (T0.2-c7, 18 exemplos): rotas Captain que leem conversa, exceto `captain/tasks`. Cobre `agent_sessions#show`, `message_reports#create`, `faq_suggestions` (index, show, approve), `conversations/:id/inbox_assistant` e `copilot_threads`/`copilot_messages` (caracterização de vazamento). Negativas para agente B e membro sem grant; controle de inbox não marcada; RubyLLM espionado.
- `.context/evidence/g0/11-t02-captain.md`: rotas, mecanismo com `arquivo:linha`, resultados por execução e pendências.
- `.context/evidence/g0/11-logs/`: logs das execuções 1 a 5, debug e RuboCop da c7.

## Changed

- Nenhum arquivo de `app/`, `config/`, `enterprise/` ou `lib/` foi alterado nesta tarefa.

## Fixed

- Nada.

## Tests

- `scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/captain_scope_spec.rb` (Ruby 3.4.4 do toolchain): exit 0 em 2 de 5 execuções. Execuções 4 e 5: 18 exemplos, 0 falhas. Execuções 1 e 3: exit 1 (7 e 9 falhas). Execução 2: exit 1 (1 falha, `RecordNotUnique` no fixture por telefone já commitado no banco compartilhado). Causa das falhas não identificada; detalhes em `evidence/g0/11-t02-captain.md`, seção 4.
- `ruby -c spec/connecta/captain_scope_spec.rb`: Syntax OK.
- RuboCop (`env -i` com as variáveis `BUNDLE_*` do launcher): 1 arquivo, sem ofensas (depois de `rubocop -a` e correção manual de `RSpec/LetSetup`).
- `git diff --check` e `git diff --no-index --check /dev/null spec/connecta/captain_scope_spec.rb`: sem saída.

## Docs

- `.context/evidence/g0/11-t02-captain.md`: criado (evidência da c7).

## Known issues

- Vazamento (caracterizado, não corrigido): `POST captain/copilot_threads` e `POST captain/copilot_threads/:id/copilot_messages` aceitam `conversation_id` de conversa fora do escopo do usuário e enfileiram `Captain::Copilot::ResponseJob` com esse id. O contexto do modelo recebe ID da conversa e do contato. Ver evidência 11, seção 1.
- Divergência de status (não corrigida): `captain/agent_sessions#show` e `captain/message_reports#create` negam leitura com 401 nativo; a decisão 002 pede 404. Ver evidência 11, seção 3.

## T0.3 · corte temporal (Coder de transferência)

### Added

- `app/services/connecta/transfer/local_transaction.rb`: `Connecta::Transfer::LocalTransaction`. Lock `pg_advisory_xact_lock` por (inbox, contato); origem `active → transferring → transferred_out` e destino `pending_activation` na mesma transação.
- `app/services/connecta/transfer/incoming_hook.rb`: mensagem entrante Baileys de contato individual toma o mesmo lock e grava na conversa do escopo não terminal do par. O handler inteiro roda em transação, porque o lock tem de valer até o commit da mensagem.
- `app/services/connecta/transfer/installer.rb`: instala o hook só em test; chamado só pela spec.
- `spec/connecta/transfer_cutover_spec.rb`: 9 exemplos (5 repetições de corrida com 20 mensagens, sanity, mensagem em voo determinística, 2 caminhos de erro).
- `.context/evidence/g0/10-t03-corte.md` e `.context/evidence/g0/10-logs/`.

### Tests

- `run-13-final-transfer.log`: 9 exemplos, 0 falhas (versão anterior à reescrita final).
- `run-14-final-com-regressao-scope.log`: spec + `scope_policy_query_spec.rb`, 39 exemplos, 0 falhas.
- Controles negativos (`run-9`, `run-11`, `run-12`): sem transação ou sem lock PG, a corrida passa, mas o exemplo determinístico falha. Ver evidência 10, seção 4.
- RuboCop da rodada anterior à reescrita: 10 ofensas, só na spec. A reescrita trata todas, mas RuboCop e spec **não foram revalidados** (disco cheio, ver evidência 10, seção 7).

### Known issues

- Versão final da spec sem execução pelo runner: `EDQUOT` no `/tmp` impediu qualquer shell depois do run-14.
- Lock de contato em Redis fica fora da prova na spec (inanição do MockRedis). Em produção continua ativo.
- A transferência não resolve a conversa de origem; isso fica para o T0.7.

## T0.2-c8 · chat interno sem conteúdo de conversa marcada (G0)

### Added

- `spec/connecta/internal_chat_scope_spec.rb`: 6 exemplos. Busca e listagem do chat interno não devolvem texto de conversa da inbox marcada (agente B e membro sem grant); controle positivo; `parent_id` e reação com id de mensagem do núcleo são recusados com 404 e nada é gravado.
- `.context/evidence/g0/12-t02-chat-interno.md` e `.context/evidence/g0/12-logs/` (EVID-7 do chat interno).

### Tests

- `run-1-spec.log`: 6 exemplos, 0 falhas, pelo runner com lock.
- RuboCop da spec: 0 ofensas (`rubocop-spec.log`).

### Known issues

- EVID-7 (chat interno): não lê conteúdo de conversa. Verificado por leitura (grep sem ocorrências ao núcleo) e pelos 6 exemplos. Caminhos sem exemplo (threads, pin, drafts etc.) só por leitura. Ver evidência 12.
- Nenhum vazamento encontrado; nenhum código de app foi alterado.

## T0.3 · fechamento da validação (Coder, 2026-10-23)

### Changed

- `spec/connecta/transfer_cutover_spec.rb`: dados únicos por execução (`run_id` nas paths das unidades e no nome da inbox; `run_digits` no LID e no telefone). A limpeza remove as unidades pelo prefixo.
- `spec/connecta/transfer_cutover_spec.rb`: o `after` termina com a checagem de sobras por conta (todas as tabelas com `account_id`), por prefixo de unidade e por inbox. O resultado tem de ser `{}`.

### Docs

- `.context/evidence/g0/10-t03-corte.md`: estado final FECHADO; §6 (limpeza) e §7 com os resultados e os logs.

### Tests

- `run-17-transfer-final.log`: `transfer_cutover_spec.rb`, 9 exemplos, 0 falhas, exit 0.
- `run-18-transfer-mais-scope-policy-final.log`: spec + `scope_policy_query_spec.rb`, 39 exemplos, 0 falhas, exit 0.
- `rubocop-t03-fechamento.log`: RuboCop em `app/services/connecta/transfer/*.rb` e no spec, sem ofensas.
- `git status --short` sem alteração rastreada; `git diff --check` sem saída.

### Known issues

- A checagem de sobras passou com zero, mas não foi testada com uma sobra induzida. Ela mostra o estado da limpeza; não prova que acusaria uma sobra.
- Os `msg-N` (source ids) continuam fixos. São únicos só porque a busca é por inbox e a inbox é única por execução.
- Limites da seção 6 da evidência 10 seguem valendo (lock de contato em Redis fora da prova, origem não resolvida, hash de 64 bits do advisory lock).

## T0.2-c1 · socket: eventos de conversa e mensagem (G0)

### Tests

- Validado sem alterar código: `spec/connecta/scope_socket_spec.rb` 12/0 (`09-logs/run-7-a-socket.log`); `scope_policy_query_spec.rb` sozinha 30/0 (`09-logs/run-8-b-policy-alone.log`); combinada de 4 arquivos 140/0 em 3 min 02 s (`09-logs/run-9-c-combined.log`). Todas pelo runner com lock.
- RuboCop em `socket_hook.rb`, `installer.rb` e `scope_socket_spec.rb`: 0 ofensas (`09-logs/rubocop-09-final.log`).

### Docs

- `.context/evidence/g0/09-t02-socket.md`: eventos cobertos (16 no mapa de `socket_hook.rb`) e não cobertos com `file:line`, resultados por run e explicação de run-4/run-5.

### Known issues

- run-4 (53 falhas) e run-5 (25 falhas) não reproduziram em série; mecanismo não identificado. Detalhes na evidência 09, seção 4.
- Fora do filtro do socket, com decisão pendente: `conversation.mentioned` (entrega `push_event_data` ao mencionado), notificações e `conversation.unread_count_changed`. Ver evidência 09, seção 3.
- 13 dos 16 eventos do mapa não têm exemplo de spec; cobertos só pela leitura do código.

## T0.2-c4 · notificações de conversas marcadas (G0)

### Added

- `spec/connecta/scope_notifications_spec.rb`: 11 exemplos. Criação, nova mensagem e atribuição notificam só quem o Gate permite ler (agente A e acompanhar); agente B e membro sem grant ficam de fora; controle em inbox não marcada; push e email só para quem o Gate permite; listagem `GET notifications` de B não mostra conversa de A; menção de A a B.
- `.context/evidence/g0/13-t02-notificacoes.md` e `.context/evidence/g0/13-logs/` (EVID-13: notificações e menção).

### Tests

- `run-1-spec.log`: 11 exemplos, 0 falhas, pelo runner com lock.
- RuboCop da spec: 0 ofensas (`rubocop-spec.log`).

### Known issues

- ACHADO F1: admin nominal recebe notificação de conversa da inbox marcada (`gate.rb:24`); o ADR 002 não admite isso na listagem. Decisão humana pendente (bloquear ou atualizar o ADR).
- ACHADO F2: menção a agente B em nota privada adiciona B como participante sem passar pelo Gate (`mention_service.rb:18`, `:87-91`). A notificação para B não é gerada (o builder barra).
- ACHADO F3: `GET conversations?conversation_type=participating` lista a conversa do setor A para B depois da menção (`conversation_finder.rb:151-152` descarta o filtro de permissão).
- Nenhum código de app foi alterado; os achados ficam para a c5.

## T0.7-s · tabelas e modelos de transferência e despacho (G0, Coder, 2026-10-23)

### Added

- `spec/connecta/support/g0_transfer_schema.rb`: `Connecta::G0TransferSchema.ensure!` cria, sem alterar nem remover nada, `connecta_g0_transfers` (índice parcial único em `source_conversation_id` para os estados abertos) e `connecta_g0_outbound_dispatches` (índice único em `message_id`).
- `app/services/connecta/transfer/transfer_record.rb` e `outbound_dispatch_record.rb`: registros do spike, com `state` validado pela lista `STATES`.
- `spec/connecta/transfer_schema_smoke_spec.rb`: idempotência do `ensure!`, índice parcial, índice único e validação de estado.

### Changed

- `scripts/connecta/g0_test_env.sh:209`: `G0_EXTRA_TABLES` com 9 nomes; única linha alterada no runner. Decisão 001 atualizada.

### Tests

- `transfer_schema_smoke_spec.rb` pelo runner com lock: 4 exemplos, 0 falhas (`14-logs/smoke-run-1.log`).
- `transfer_cutover_spec.rb` pelo runner com lock: 9 exemplos, 0 falhas (`14-logs/cutover-run-1.log`).
- RuboCop nos 4 arquivos `.rb` novos: 0 ofensas (`14-logs/rubocop-t07s.log`).

### Known issues

- As tabelas `connecta_g0_transfers` e `connecta_g0_outbound_dispatches` existem só no banco de teste G0, criadas pelo helper create-only; não há migração. Os registros herdam de `Connecta::Scope::BaseRecord` (base do spike), não de `ApplicationRecord`.

## T0.2-c10 · complementos da B2 (G0, Coder, 2026-10-23)

### Added

- `spec/connecta/scope_b2_complements_spec.rb` (12 exemplos): lacunas da seção 3 da B2 que pedem só exemplos. Cobre criação e atributos de contato (agente A, agente B, membro sem grant), etiquetas em lote com mistura A/B, admin nominal na inbox marcada (leitura, membros, atualização com e sem papel de administrador), webhooks e relatório v2, agendadas de agente com grant e não lidas com a flag desligada.
- `.context/evidence/g0/15-t02-b2-complementos.md`: tabela lacuna → exemplo → resultado, execuções e pendências.

### Tests

- `scope_b2_complements_spec.rb` pelo runner com lock: 12 exemplos, 0 falhas (`15-logs/run-3-b2-complementos.log`). Uma execução anterior falhou por parâmetro aninhado na própria spec (`15-logs/run-1-b2-complementos.log`).
- RuboCop na spec nova: 0 ofensas (`15-logs/rubocop-b2-complementos.log`).

### Known issues

- ACHADO-1: admin nominal com papel de agente faz `PATCH` na inbox marcada; a auditoria grava `allow` em `inbox_update` e o nativo responde 401 (`inbox_hook.rb:9`, `inboxes_controller.rb:3,7`). Não há vazamento de dados; não corrigido.
- Leitura da inbox (`show`) e lista de membros não geram registro de auditoria, por desenho. Decisão pendente.

## T0.2-c2a · socket: mention, contagem de não lidas e metadados de admin (G0, Coder, 2026-10-23)

### Added
- `app/services/connecta/scope/admin_metadata_broadcast_job.rb`: job próprio que entrega metadados de conversa da inbox marcada a admins. Não usa `ActionCableBroadcastJob`, que relê a conversa inteira em `conversation.read/updated`, `team.changed`, `assignee.changed` e `conversation.status_changed` (`app/jobs/action_cable_broadcast_job.rb:26`).
- Admins (nativos e nominais verificados) recebem em inbox marcada só: em mensagem, `id` e `conversation_id`; em conversa, `id`, `inbox_id`, `status` e `org_unit_id`; em ambos, `account_id`. Campos e origem em `.context/evidence/g0/09-t02-socket.md` §7.2.

### Changed
- `app/services/connecta/scope/socket_hook.rb`: `conversation.mentioned` só chega a quem o Gate lê (admin não recebe); `conversation.unread_count_changed` segue o filtro de leitores e não envia sinal para conversa apagada de inbox marcada.
- `spec/connecta/scope_socket_spec.rb`: exemplos de admin trocados para o contrato de metadados; novos exemplos de mention, contagem de não lidas, payload reduzido e controles de inbox não marcada. 21 exemplos.

### Tests
- `spec/connecta/scope_socket_spec.rb`: 21 exemplos, 0 falhas (2 execuções, `09-logs/run-c2a-1-socket.log`, `run-c2a-3-socket-final.log`).
- `spec/connecta/scope_policy_query_spec.rb` + `scope_http_filter_spec.rb`: 64 exemplos, 0 falhas (`09-logs/run-c2a-2-regressao.log`).
- RuboCop nos 3 `.rb` tocados: sem ofensas (`09-logs/rubocop-09-c2a.log`).

### Known issues
- Job nativo `ActionCableBroadcastJob` continua recarregando o payload em eventos de atualização; produção precisa de decisão (job próprio ou ajuste no core). Ver `.context/evidence/g0/09-t02-socket.md` §7.4.
- Sem exemplo de spec para conversa apagada em inbox marcada; sem teste de mutação; frontend não verificado com o payload reduzido.

## T0.2-c2b · socket: digitação, contatos e presença (G0, Coder, 2026-10-23)

### Changed
- `app/services/connecta/scope/socket_hook.rb`: digitação e gravação de conversa marcada (`conversation.typing_on`, `typing_off`, `recording`) passam pelo filtro do Gate (`CONVERSATION_EVENTS`); admins ficam de fora. Contato vinculado a inbox marcada (`contact.created`, `updated`, `merged`, `group_synced`, `deleted`) sai do stream `account_<id>` e vai só a quem o `ContactVisibility` permite (`CONTACT_EVENTS`, `broadcast`). Contato sem vínculo segue o nativo. `installer.rb` sem alteração.
- `spec/connecta/scope_socket_spec.rb`: 9 exemplos novos (4 de digitação e gravação, 5 de contato) e helper `broadcast_tokens`. 30 exemplos.

### Tests
- `spec/connecta/scope_socket_spec.rb`: 30 exemplos, 0 falhas (`09-logs/run-c2b-1-socket.log`).
- Mutação (typing e contato vinculado desligados): 7 falhas esperadas, controles passam; arquivo restaurado e conferido com `cmp` (`09-logs/run-c2b-2-mutacao-sem-typing-e-contato.log`).
- `spec/connecta/scope_related_http_spec.rb`: 64 exemplos, 0 falhas (`09-logs/run-c2b-3-related-http.log`).
- RuboCop nos 2 `.rb` tocados: sem ofensas (`09-logs/rubocop-09-c2b.log`).

### Docs
- `.context/evidence/g0/09-t02-socket.md` §8: destinatários antes e depois, presença caracterizada, tabela de cobertura do socket (evento → código → exemplo).

### Known issues
- `contact.deleted` sem exemplo e com janela de corrida: `contact_inboxes` usa `destroy_async` (`app/models/contact.rb:62`) e o listener roda logo após o commit (`contact.rb:74`); se o vínculo já sumiu, o evento cai no stream da conta. Decisão pendente (evidência 09 §8.4, item 1).
- Presença (`app/channels/room_channel.rb:19-25`) não é filtrada: leva ids e disponibilidade de usuários da conta e ids de contatos online a qualquer assinante. Só caracterizada (evidência 09 §8.5).
- Digitação mantém o token do contato (cliente); candidatos de contato são membros da inbox (evidência 09 §8.4, itens 3 e 4).

## T0.7b · despacho de saída com barreira de transferência (G0, Coder, 2026-10-23)

### Added

- `app/services/connecta/transfer/outbound_dispatch.rb`: `Connecta::Transfer::OutboundDispatch`. `enqueue!` cria a linha `queued` (idempotente); `claim!` troca `queued` por `dispatching` numa única instrução só se a conversa tem escopo `active`, senão `parked`; `resolve!` grava `accepted`, `failed` ou `uncertain`; `prepare_transfer!` parka os `queued`, espera por `dispatching` e levanta `ConflictError` com `uncertain`. `MessageHook` chama `enqueue!` na criação da mensagem.
- `app/services/connecta/transfer/send_reply_hook.rb`: `Connecta::Transfer::SendReplyHook`, prepend em `SendReplyJob`. Só o vencedor do claim chama o conector; timeout e 409 "já em processamento" viram `uncertain`, outro erro vira `failed`, e nada é reenviado.
- `spec/connecta/outbound_dispatch_spec.rb`: 10 exemplos (9 com o fixture de escopo e 1 concorrente sem transação externa).
- `.context/evidence/g0/17-t07b-despacho.md`: decisões, runs, controles negativos e limites.

### Changed

- `app/services/connecta/transfer/installer.rb`: `install!` (só em test) passa a prepend `Message` e `SendReplyJob`, além do `IncomingHook` de T0.3.

### Tests

- `outbound_dispatch_spec.rb` + `transfer_cutover_spec.rb` pelo runner com lock: 19 exemplos, 0 falhas, exit 0 (`17-logs/run-8-pair-final-409.log`).
- Controles negativos, restaurados depois: sem checagem de `active` falha o late worker (`run-4`, `spec:36`); sem `state = 'queued'` falham 4 exemplos, incluindo a corrida (`run-6`).
- RuboCop nos 4 arquivos tocados: 0 ofensas (`17-logs/rubocop-t07b-final.log`).

### Known issues

- `prepare_transfer!` ainda não está ligado a `LocalTransaction.begin!`: integração posterior (T0.7a).
- Reenvio manual (retry e reações) em inbox marcada não cria linha nova: o índice único em `message_id` bloqueia. Decisão pendente.
- O status visível de `parked` ("não enviada: chamado transferido") é UI, Fase 5.

## T0.2-c5 · notificações, menções e participating no escopo (G0, Coder, 2026-10-23)

### Added

- `app/services/connecta/scope/notification_hook.rb`, `mention_hook.rb` e `conversation_finder_hook.rb`: hooks de teste para barrar notificação de admin nominal, descartar menção sem leitura pelo Gate e reaplicar o escopo à listagem `participating`.

### Changed

- `app/services/connecta/scope/gate.rb` e `installer.rb`: decisão `notifiable?` e instalação dos hooks da c5.
- `spec/connecta/scope_notifications_spec.rb`: 17 exemplos; F1–F3 agora são asserções negativas, inclusive participante preexistente, com controles de menção e `participating` em inbox não marcada.
- `.context/evidence/g0/13-t02-notificacoes.md`: seção c5 com correções e validação final.

### Tests

- `scope_notifications_spec.rb`: 17 exemplos, 0 falhas, exit 0 (`13-logs/c5-run-3-notificacoes.log`).
- `scope_policy_query_spec.rb` + `scope_http_filter_spec.rb`: 64 exemplos, 0 falhas, exit 0 (`13-logs/c5-run-4-regressao.log`).
- RuboCop nos 6 `.rb` da c5: sem ofensas, exit 0 (`13-logs/c5-rubocop.log`).

## T0.7a · barreira de ativação e despacho em voo (G0, Coder, 2026-10-23)

### Added

- `.context/evidence/g0/16-t07a-ativacao.md`: o que foi construído (métodos e transições de `TransferRecord`), prova de cada AC por linha do spec, todos os runs (incluindo o run 5 com 6 falhas) e limites.
- `.context/evidence/g0/16-logs/`: `activation-cutover-run-11.log`, `run-12.log`, `run-13.log` (par 3×) e `rubocop-t07a-run-3.log`.

### Tests

- `transfer_activation_spec.rb` + `transfer_cutover_spec.rb` pelo runner com lock, 3 vezes em sequência: 19 exemplos, 0 falhas, exit 0 (runs 11, 12, 13).
- Referência: run 5 histórico com 19 exemplos e 6 falhas (5 de activation + `transfer_cutover_spec.rb:182`); runs 8, 9 e 10 do Coder de flake: 19/0; activation sozinha 10/0, cutover sozinha 9/0.
- RuboCop (`env -i` com `BUNDLE_GEMFILE`, `BUNDLE_PATH`, `BUNDLE_FROZEN=true` do launcher) em `app/services/connecta/transfer/local_transaction.rb` e `spec/connecta/transfer_activation_spec.rb`: 0 ofensas, exit 0.
- `git status --short`: só `??` (nada rastreado alterado); `git diff --check`: vazio.

### Known issues

- `prepare_transfer!` (T0.7b) ainda não ligado a `LocalTransaction.begin!`: wiring é a tarefa T0.7c.
- Cancelamento de agendados/recorrentes da origem não tratado neste turno (0 ocorrências de `schedul|recurr|cancel` no código); origem travada via Gate + conversa resolvida.
- Flake geral do run 5 em investigação por outro Coder (`ps-sampler-run-7.log`); nenhum arquivo compartilhado alterado aqui.

## T0.7c · integração transferência ↔ despacho em voo (G0, Coder, 2026-10-24)

### Added

- `app/services/connecta/transfer/local_transaction.rb`: `take_origin!`, `prepare_conversation!`, `settle_begin!`
  (mais `resume!`, `recheck_conversation!`, `load_open_record!`, `abort_open_record!` e suportes). `begin!` marca
  `transferring` sob o lock do T0.3, estaciona `queued` via `OutboundDispatch.prepare_transfer!` (contrato estável,
  sem reescrita) e retorna `WAIT` com `dispatching` em voo (`awaiting_dispatch`, `resume!` reavalia) ou relança com
  `uncertain` (origem volta a `active`, pedido a `aborted`). `commit_local!` revalida a barreira antes de gravar e
  nunca commita com despacho pendente/incerto; origem nunca reabre após o commit, destino segue
  `pending_activation`. Inbox não marcada segue sem barreira. Detalhes em
  `.context/evidence/g0/18-t07c-integracao.md`.
- `.context/evidence/g0/18-t07c-integracao.md`: seção código (explicitamente NÃO VALIDADO), mapeamento aos ACs e
  limites.

### Tests

- NÃO EXECUTADO (por instrução do humano): nenhum spec, RuboCop ou build rodou nesta tarefa. Validação
  (`transfer_activation_spec.rb`, `outbound_dispatch_spec.rb`, `transfer_cutover_spec.rb` + RuboCop) é tarefa
  posterior da fase.
- `git diff --check`: sem saída. `git status --short`: só `??` (nada rastreado alterado). `/tmp`: 2,6 GB livres
  antes de começar, nada apagado.

### Known issues

- `activate!`/`mark_stuck!` ainda usam `@record.id` (limite pré-existente da T0.7a); outra instância após
  `commit_local!` segue fora de escopo.
- Cancelamento de agendadas/recorrentes da origem e reenvio manual (retry/reações) seguem pendentes (limites
  herdados da T0.7a/T0.7b).

## T0.2-c7b · complemento Captain/Copilot (G0, Coder, 2026-10-23/24)

### Added

- `app/services/connecta/scope/copilot_hook.rb`: guard no `create` nega `conversation_id` fora do escopo antes de
  persistir/enfileirar (404 em inbox marcada sem leitura, 404 em ID inexistente na conta).
- `app/services/connecta/scope/copilot_chat_hook.rb`: contexto do modelo sem IDs alheios quando o Gate nega.
- `app/services/connecta/scope/copilot_tool_hook.rb`: `execute` de `get_conversation`/`get_contact`/`search_contacts`
  devolve `not found` sem conteúdo quando o alvo está fora do escopo do usuário.
- `app/services/connecta/scope/captain_http_hook.rb`: `authorize_conversation` com Gate antes do nativo
  (`agent_sessions#show`, `message_reports#create` sem acesso em inbox marcada dão 404).
- `app/services/connecta/scope/inbox_hook.rb`: auditoria nominal diferida — `allow` só após a autorização nativa;
  sem `allow` fantasma no `update` negado; `inbox_create` WhatsApp nega não-admin antes de qualquer I/O.
- `app/services/connecta/scope/installer.rb`: liga os 5 hooks e o `rescue_from(Denied)` nos 4 controllers Captain.
- `.context/evidence/g0/19-t02-captain-complemento.md`: código documentado como NÃO VALIDADO, com pontos de teste.

### Tests

- NÃO EXECUTADO (por instrução do humano): nenhum spec, RuboCop ou build rodou nesta tarefa. Validação funcional
  (Copilot/Captain/inbox_update) é tarefa posterior da fase.
- `git diff --check`: sem saída. `git status --short`: só `??` (nada rastreado alterado). `/tmp`: 2,6 GB livres
  antes de começar, nada apagado.

### Known issues

- `spec/connecta/captain_scope_spec.rb:164-190` segue caracterizando o vazamento (não editada aqui); a prova da
  correção é tarefa posterior.
