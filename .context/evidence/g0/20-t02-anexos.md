# 20 — Anexos T0.2-c3: rota autorizada (IMPLEMENTADO / NÃO VALIDADO)

- Data (UTC): 2026-10-24.
- TASK_ID: g0-t02-c3.
- Natureza: **registro documental**. Nenhum código foi alterado e nenhum spec/lint/build foi executado nesta tarefa.
- Status: **IMPLEMENTADO (código) / NÃO VALIDADO (funcional)**.
- Base de leitura (somente estes 4 arquivos; o Installer **não** foi lido — outra frente o edita):
  - `app/services/connecta/scope/attachment_token.rb` (24 linhas)
  - `app/services/connecta/scope/attachment_url_hook.rb` (53 linhas)
  - `app/services/connecta/scope/active_storage_guard.rb` (30 linhas)
  - `app/services/connecta/scope/attachment_downloads_controller.rb` (50 linhas)
- Checagem de espaço (somente leitura, sem apagar): `df -h /tmp` → `tmpfs 7.6G, 5.1G usados, 2.6G livres, 67%` em 2026-10-24.
- Antecedente: caracterização original em `.context/evidence/g0/05-evid4-anexos.md` (não repetida aqui); código entregue segundo log em `/home/thanos/.local/state/opencode-coder/20261024T002045-1842229` (ruby -c citado lá, **não** reexecutado aqui).

## 1. APIs e rota (código lido, não prova funcional)

### 1.1 Emissão e leitura de token — `attachment_token.rb:6-24`

- `Connecta::Scope::AttachmentToken::PURPOSE = 'connecta_g0_attachment_download'` (`:7`).
- `Connecta::Scope::AttachmentToken::TTL = 5.minutes` (`:8`).
- `issue(attachment:, user:, account:, epoch:)` (`:10-19`): monta payload com `attachment_id`, `blob_id` (`attachment.file.blob.id`), `user_id`, `account_id`, `epoch` e gera com `Rails.application.message_verifier('ActiveStorage').generate(payload, purpose: PURPOSE, expires_in: TTL)`.
- `read(token)` (`:21-23`): `Rails.application.message_verifier('ActiveStorage').verified(token, purpose: PURPOSE)` (retorna o payload ou falsy; expiração verificada pelo próprio verifier).

### 1.2 Reescrita de URL — `attachment_url_hook.rb:5-53`

- Sobrescreve `file_url` (`:6-10`), `thumb_url` (`:12-16`), `download_url` (`:20-24`) e `inline_audio_url` (`:28-33`, privado); cada um tenta `connecta_scope_authorized_url` e cai para `super` (nativo) quando ela retorna `nil`.
- `connecta_scope_authorized_url(thumb: false)` (`:35-52`): retorna `nil` (→ nativo) quando: sem `Current.user` (`:37`); helper `connecta_scope_attachment_download_url` inexistente (`:38`); sem `message.conversation` (`:41`); inbox **não** marcada por `Connecta::Scope::Projection.marked?(conversation.inbox_id)` (`:42`). Com tudo presente, lê `Connecta::Scope::UserAuthEpoch.find_by(user_id:)` (`:44`), emite token via `AttachmentToken.issue` com `epoch_row&.epoch || 0` (`:45-46`) e monta `connecta_scope_attachment_download_url(account_id:, attachment_id:, token:, thumb: 1?)` (`:47-49`). `rescue StandardError → nil` (`:50-51`).
- Nome da rota (helper citado no código): `connecta_scope_attachment_download_url`. O desenho da rota pelo Installer **não** foi lido nesta tarefa (outra frente o edita); o hook só a usa quando ela existe (`:38`). Ligação test-only do Installer vale aqui **só como relato anterior**, não como fato verificado.

### 1.3 Download autorizado — `attachment_downloads_controller.rb:7-50`

- `Connecta::Scope::AttachmentDownloadsController < Api::V1::Accounts::BaseController` (`:7`); `show` (`:8-21`):
  1. `Current.account.attachments.find_by(id: params[:attachment_id])`; `raise Connecta::Scope::Denied, :not_found` se ausente ou sem `file.attached?` (`:9-10`).
  2. `Projection.marked?(conversation.inbox_id)` exigido (`:13`).
  3. `connecta_scope_verify_token!` (`:15`) + Gate (`:16-18`, ver §3).
  4. `connecta_scope_serve!` (`:20`): `send_data` dos bytes pelo próprio app — **nunca redirect** para URL global de blob (comentário `:6`).
- `connecta_scope_verify_token!` (`:25-39`): relê token (`AttachmentToken.read(params[:token])`), relê `UserAuthEpoch` do `current_user` e exige tudo ao mesmo tempo (`:28-33`): payload é `Hash`, epoch viva (`!epoch_row.nil?`, `revoked_locally_at.nil?`), `attachment_id`/`blob_id`/`user_id`/`account_id` (`Current.account.id`)/`epoch` iguais. Falha → `AccessAudit.create!(user_id:, conversation_id:, surface: 'attachment', access_path: 'attachment_download', decision: 'deny')` + `raise Denied, :not_found` (`:36-38`).
- `connecta_scope_serve!` (`:41-49`): com `params[:thumb]` serve `attachment.file.representation(resize_to_fill: [250, nil]).processed` inline; sem thumb serve `blob.download` inline (`filename`, `content_type`, `disposition: :inline`).

### 1.4 Bloqueio legado — `active_storage_guard.rb:6-30`

- `show` (`:7-13`): blob de inbox marcada → `head :not_found`; senão `super` (nativo).
- `connecta_scope_marked_blob?` (`:17-29`): `blob.attachments.where(record_type: 'Attachment').pluck(:record_id)` (`:20`); `false` se vazio (`:21`); `Projection.marked_inbox_ids`, `false` se vazio (`:23-24`); nega quando `::Attachment.joins(message: :conversation).where(id: record_ids, conversations: { inbox_id: marked_ids }).exists?` (`:26`). `rescue StandardError → false` (`:27-28`, ou seja, em erro segue nativo).
- Comentário do arquivo (`:1-5`): prepend nos 4 controllers de redirect/proxy de blobs e representations do ActiveStorage, instalado só pelo spike G0; blob compartilhado com inbox marcada também nega; Disk/direct_uploads ficam nativos (decisão pendente).

## 2. Vínculo usuário + conta + epoch + expiração (código)

- Emissão prende `user_id`, `account_id`, `epoch` (do usuário no momento da emissão) e `attachment_id`/`blob_id` (`attachment_token.rb:11-17`).
- Expiração curta no envelope assinado: `expires_in: TTL` = 5 minutos (`attachment_token.rb:8,18`).
- Download revalida a cada requisição contra o banco vivo: `epoch_row.epoch`, `revoked_locally_at.nil?`, `current_user.id`, `Current.account.id`, `blob.id` (`attachment_downloads_controller.rb:28-33`). Comentário do token (`attachment_token.rb:4-5`): revogação/transferência invalida mesmo sem expirar; conhecer URL/token nunca basta. **Isto é o que o código diz; não há prova funcional nesta tarefa.**

## 3. Checagem Gate (código)

- `Connecta::Scope::Gate.new(current_user).read?(conversation, access_path: 'attachment_download')` exigido após o token (`attachment_downloads_controller.rb:16-18`); negado vira 404 (`Denied, :not_found`; comentário `:5-6` cita decisão 002 para leitura).

## 4. Limites observados (sem inventar garantia funcional)

1. **Sem validação funcional aqui**: nenhum spec, `ruby -c`, lint ou build foi executado; o `ruby -c` citado no log anterior não foi reexecutado.
2. **Rota/Installer não verificados aqui**: o desenho da rota e o caráter test-only do Installer valem só como relato anterior; outro Coder os edita.
3. **Sem `Current.user` → nativo**: jobs, serviços externos e mailers seguem o comportamento nativo (`attachment_url_hook.rb:1-4,18-19,37`).
4. **Disk/direct_uploads nativos**: URLs curtas de serviço seguem nativas por comentário do guard (`active_storage_guard.rb:5`); decisão pendente.
5. **Afirmações de comentário, não provadas**: negar URL legada emitida antes da proteção, contaminação fail-closed de blob compartilhado e "serve bytes, nunca redirect" são o que código/comentário dizem; sem teste, não são garantia.
6. **Rescue → nativo**: erro no hook (`:50-51`) ou no guard (`:27-28`) cai para o comportamento nativo; não se afirma disponibilidade nem negação nesses caminhos.
7. **Escopo herdado da base 05**: S3/GCS/Azure não medidos; sem dados reais nem Baileys real; G0 segue aberto — nada aqui aprova ACL, transporte ou Fase 1.

## 8. Correções pós-26 (T0.2-c3, TASK_ID g0-t02-c3) — CÓDIGO CORRIGIDO, NÃO VALIDADO EM SPEC

- **Causa 1 — rota de download nunca ativada (5 das 8 falhas: `:74`, `:105`, `:121`, `:203`, `:288/:301/:316`)**:
  `installer.rb` desenhava a rota com `Rails.application.routes.append`, mas `append` só entra em vigor no
  próximo `finalize!` (`route_set.rb:435-437,455-457`) — sem `reload_routes!` a rota nova respondia 404 e o
  helper `connecta_scope_attachment_download_url` seguia inexistente, então:
  (a) autorizado com token/Gate válidos recebia 404 (`:74` e `:203` na janela) sem chegar ao `Gate`/`send_data`;
  (b) sem-auth recebia 404 da rota inexistente em vez do 401 nativo (`:105` — o controller nunca era alcançado);
  (c) auditoria `deny` ficava 0 porque o request nem batia no `verify_token!` (`:121` — `Gate#decide` audita em
  `surface: 'conversation'`; o `deny` em `surface: 'attachment'` só existe no caminho de vínculo falho do
  controller, que nunca era alcançado);
  (d) hook de serialização recaía no nativo porque `respond_to?` do helper era falso (`:288/:301/:316`).
  **Correção** (`installer.rb`): `Rails.application.reload_routes!` após o `append` (flag anti-duplicação
  preservada; `rescue` restaura a flag e relança). Vínculo token (`attachment_id/blob_id/user_id/account_id/epoch`
  + expiração 5 min) e `Gate.read?` inalterados — download segue exigindo tudo e servindo bytes inline,
  sem redirect global. `Current.user` ausente segue nativo (limite documentado).
- **Causa 2 — representation legada marcada virava 500 (`:369`)**:
  o `before_action :set_representation` nativo (`representations/base_controller.rb`) chama
  `@blob.representation(variation_key).processed` e qualquer variante inválida/ausente levantava ANTES do
  `show` do guard — que só negava com `@blob` já resolvido. **Correção** (`active_storage_guard.rb`): novo
  módulo `RepresentationsGuard` (inclui o guard base; prepended SÓ nos dois controllers de representations
  via `installer.rb`) nega marcado no próprio `set_representation`, antes do `.processed`; assinatura inválida
  mantém o nativo (`head :not_found`). Blobs seguem no guard original (só `show`). Controle não marcado segue
  nativo (proxy legado `ok`). Legacy marcado nega 404, nunca 500 nem URL global.
- **Ajustes de spec (SOMENTE contrato/setup provado, sem mudar cobertura — nenhum exemplo eliminado)**:
  comentário no exemplo `:121` (o `deny` esperado é o do `verify_token!` em `attachment/attachment_download`;
  `Gate` audita em `surface: 'conversation'` e nunca é consultado quando o vínculo já negou — nenhum `allow`
  fabricado, nenhum Gate stubado); comentário no exemplo `:105` (401 vem do DeviseTokenAuth nativo sem
  credencial; o controller nunca é alcançado — aceitar 404 seria mascarar contrato nativo, por isso o 401 é
  mantido). Teste de vazamento preservado em todos os negativos (`not_to include(BODY)`).
- **Não alterado nesta tarefa**: `attachment_token.rb` (vínculos+TTL), `attachment_url_hook.rb` (hook+fallback
  nativo), `attachment_downloads_controller.rb` (verify+Gate+serve) — causa comprovadamente fora deles.
  Captain/fixtures/runner/schema intocados. Execução de specs pendente (tarefa de validação posterior explícita).
- Validação aqui: `git diff --check` limpo; `ruby -c` 3.4.4 OK nos 5 arquivos do escopo + spec; `df -h /tmp`
  tmpfs 7.6G/5.1G/67% (leitura, sem apagar). Specs NÃO executados nesta tarefa.

## 5. O que este documento afirma / não afirma

- Afirma: os 4 arquivos existem com as APIs, helper de rota, vínculos, Gate e bloqueio acima (sintaxe/código lido em 2026-10-24).
- Não afirma: que a rota resolve, que o token expira na prática, que o Gate nega/permite corretamente, que o legado bloqueia de fato, nem que S3/GCS/Azure se comportam como Disk. Tudo isso é **validação funcional pendente** (specs próprios, tarefa posterior).
- Efeito no quadro: a frase de EVID-4 em `22-quadro-evidencias.md` que dizia rota "não implementada" passa a apontar este documento como **código sem validação** (sem fingir teste verde).

## 6. Links locais usados (existem nesta worktree)

- `app/services/connecta/scope/attachment_token.rb`
- `app/services/connecta/scope/attachment_url_hook.rb`
- `app/services/connecta/scope/active_storage_guard.rb`
- `app/services/connecta/scope/attachment_downloads_controller.rb`
- `.context/evidence/g0/05-evid4-anexos.md` (base histórica, Disk de teste)
- `.context/evidence/g0/22-quadro-evidencias.md` (EVID-4 atualizada para apontar aqui)

## 7. Spec escrita NÃO EXECUTADA — sintaxe real 3.4.4 (2026-10-24, TASK_ID g0-t02-c3)

- Arquivo: `spec/connecta/attachment_download_scope_spec.rb` (397 linhas, estável, sem edição nesta tarefa).
- Sintaxe real (binário confirmado por `ls -l`, sem fallback 4.0.7):
  `/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c spec/connecta/attachment_download_scope_spec.rb` → `Syntax OK` (EXIT:0). Binário: `-rwxr-xr-x 233304 Oct 22 14:51`.
- Checagem de espaço (somente leitura, sem apagar): `df -h /tmp` → `tmpfs 7.6G, 5.1G usados, 2.6G livres, 67%`.
- Contagem real (sem assumir "20+ ex"): `grep -c "^[[:space:]]*it '"` → **27 exemplos escritos e NÃO EXECUTADOS**.
- O que cobre (por `describe`, Gate real sem stub, HTTP real quando executar):
  1. `autorizado recebe bytes; Gate nega sem grant` (6): A com grant recebe bytes inline; token de A com sessão de B 404; B de outro setor 404; membro sem grant 404; sem auth 401 nativo; admin nominal 404.
  2. `vínculo token × usuário/conta/anexo/blob` (6): outro usuário negado + auditado `deny`; `account_id` de outra conta negado; anexo de outra conversa negado; blob trocado invalida; assinatura quebrada 404; token ausente 404.
  3. `expiração e epoch` (4): vale em 4 min / nega em 6 min (TTL 5 min); epoch alterada invalida; `revoked_locally_at` nega; epoch removida nega (fail-closed).
  4. `transferência e revogação` (3): `transferred_out` nega; grant revogado nega; heartbeat vencido nega — todos com token ainda válido.
  5. `serialização marcada` (4): `push_event_data`/`download_url` com `Current.user` na rota autorizada + `token=`; thumb imagem com `thumb=1`; áudio `inline_audio_url` na rota autorizada; controle não marcado segue `/rails/active_storage/blobs/redirect/` nativo.
  6. `links legados` (4): redirect legado 404; proxy legado 404; representation legada 404; controle nativo segue `ok` no proxy.
- O que NÃO cobre / limites: nenhuma execução de request/spec nesta tarefa (execução funcional pendente, reservada à validação consolidada); sintaxe ≠ prova de rota, expiração, Gate ou bloqueio legado; Storage Disk local de teste, nenhuma URL externa chamada; S3/GCS/Azure não medidos; sem dados reais nem Baileys real.
- AC: AC1 sintaxe 3.4.4 concreta OK; AC2 este §7 registra casos/limites com execução pendente.

## 9. Diagnóstico do 500 + correção causa-única + validação focada (Rodada28, TASK_ID g0-t02-c3)
- Exceção real (janela rodada26A2, filtrada via context-mode/sed sem token/credencial, método da memória `sed -n`):
  `log/test.log:2409724` (e +17 ocorrências na mesma rodada) — `NoMethodError (undefined method 'attachments'
  for an instance of Account)` em `app/services/connecta/scope/attachment_downloads_controller.rb:9:in 'show'`.
  `Account` não tem `has_many :attachments` (verificado em `app/models/account.rb:65-110` — há `messages`,
  sem `attachments`), então TODO request autorizado/negado que chegava ao `show` estourava 500 antes do
  `verify_token!`/`Gate`/auditoria/`send_data` — o que explica os 17 HTTP 500 + a auditoria `deny` 0 da rodada26A2
  (o `rescue_from Denied` do Installer nunca era alcançado; sem afrouxamento de autenticação/Gate/token/epoch).
- Correção causa-única (sem bypass, sem redesenho): `attachment_downloads_controller.rb:9`
  `Current.account.attachments.find_by(...)` → `::Attachment.where(account_id: Current.account.id).find_by(...)`.
  Conta errada continua fora (find pelo `Current.account.id`); ausente/sem `file.attached?` continua
  `Denied, :not_found`; vínculo token/user/account/blob/epoch + `Gate.read?` + auditoria + `send_data` inline
  inalterados. Sintaxe 3.4.4 `Syntax OK`; `git diff --check` limpo (nos rastreados).
- Validação focada pela fila (AUTORIZAÇÃO citada, uma execução final + uma extra com motivo, sem editar launcher):
  `... g0_test_env.sh --spec --apply spec/connecta/attachment_download_scope_spec.rb` (final-3) → RSpec
  **27 examples, 1 failure** (23.69 s; EXIT 1), log integral `.context/evidence/g0/28-logs/anexos-final-3.log`.
  Falha remanescente honesta (sem loop): `:114` — `admin nominal sem leitura de detalhe recebe 404` recebeu 200
  porque `Gate#decide` (`gate.rb:29`) dá `allow` de LEITURA a `projection.admin?` (grant `admin_nominal` em
  `org_root`, válido por `granted_paths` `/raiz/...` + `state active` em `READ_STATES`) — o spec espera 404
  ("sem leitura de detalhe"), mas o contrato vigente do Gate concede leitura a admin nominal. Decisão de
  produto (mudar Gate ou spec) fora desta frente causa-única; NENHUM ajuste Gate/spec feito aqui.
  Diagnóstico `.context/evidence/g0/28-logs/anexos-diagnostico.log` (janela 17:58:51–17:59:07Z da final-3,
  filtrada sem token/credencial): 20 requests `connecta_attachments` — `Completed 200×3 / 401×1 (sem auth,
  nativo) / 404×16`, ZERO `Completed 500`, ZERO `NoMethodError`.
- Preservado: Captain 33 verde (rodada26), serialização/representação da rodada2, demais 26/27 verdes.

## 10. Alinhamento do caso admin ao plano + 27/27 verdes (TASK_ID g0-t02-c3, 2026-10-24)
- Justificativa normativa (sem mudar Gate/código): plano §5.3 "Administrador geral — Acesso a tudo, **auditado** (5.6)"
  (linhas 182-189); §5.6 "toda leitura de conversa da inbox física por caminho `administrator` grava
  `connecta_access_audits`" + "o conteúdo vem ao abrir (auditado)" (linhas 226-230); Q10 "Admin recebe só
  metadados em tempo real; conteúdo apenas por leitura auditada" (linha 873, §18.2/T3.4). O 404 da final-3 em
  `:114` contradizia essa decisão já vigente: `Gate#decide` (`gate.rb:29`) dá `allow` de LEITURA a
  `projection.admin?` e audita `allow` em `surface: 'conversation'`. Correção = expectativa do spec, não ACL:
  renomear o caso para `admin nominal com token próprio recebe 200 auditado no download`, exigir 200 + bytes
  corretos + `AccessAudit` `allow` (usuário `admin_nominal` / conversa `conv_a` / surface `conversation` /
  `access_path` `attachment_download`) e preservar token próprio/user/account/epoch/expiração (admin com token
  de outro usuário continua negado no vínculo, sem consultar o Gate; demais 26 negativos intactos — Gate/código
  inalterados).
- Resultado real (uma execução pela fila, autorização citada, sem editar launcher): `g0_test_env.sh --spec
  --apply spec/connecta/attachment_download_scope_spec.rb` (final-4) → RSpec **27 examples, 0 failures**
  (21.84 s; EXIT 0; INICIO_UTC 2026-10-24T18:02Z). Log integral `.context/evidence/g0/28-logs/anexos-final-4.log`.
  Auditoria assertada no próprio exemplo (change `allow` +1, Gate real sem stub). Validação: `ruby -c` 3.4.4 OK
  no arquivo alterado; `git diff --check` limpo; `git status --short` só `??` pré-existentes (sem commit);
  `df -h /tmp` 7.6G/67% (leitura, sem apagar). Nenhum outro spec/teste/lint/build; sem SQL manual/banco/schema.
