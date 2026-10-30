# 31 — Evidência spec-lint (TASK_ID g0-fix-spec-lint)

Somente diagnóstico + registro nos 5 arquivos próprios. Sem execução de specs, sem app/runner/schema, sem teardown, sem segredos impressos.

## 1. Arquivos (ownership desta frente)

- `spec/requests/connecta/route_inventory_spec.rb` (AC1 — classificação exata)
- `spec/connecta/attachment_download_scope_spec.rb` (JSON29: 14 ofensas)
- `spec/connecta/scope_b1_leftovers_spec.rb` (JSON29: 17 ofensas)
- `spec/connecta/scope_team_contact_spec.rb` (JSON29: 10 ofensas)
- `spec/connecta/captain_scope_spec.rb` (JSON29: 1 ofensa)
- Total JSON29 em ownership: 42 ofensas → **0** após os fixes.

Não lidos nem alterados (outra frente): `transfer_cutover_spec.rb`, `transfer_activation_spec.rb`,
`outbound_dispatch_spec.rb`, `transfer_integration_spec.rb`, `scope_related_http_spec.rb`.
Suporte compartilhado (`spec/connecta/support/`, `spec/support/connecta/`): JSON29 aponta **0 ofensas** — intacto.

## 2. AC1 — rota de download classificada sem catch-all

- Rota nova (falha exata do G2 em `route_inventory_spec.rb:204`, log `29-logs/g2-lote-1.log:62-66`):
  `GET /api/v1/accounts/:account_id/connecta_attachments/:attachment_id/download`
  `(connecta/scope/attachment_downloads#show)`.
- Fix: superfície nova `download autorizado de anexo marcado (spike G0; rota desenhada só com o Installer instalado)`
  em `route_inventory_spec.rb` (controller exato `connecta/scope/attachment_downloads`; sem prefix/path genérico).
- Fronteira de autenticação registrada na própria superfície (fonte, sem inventar):
  conta (`Api::V1::Accounts::BaseController` + vínculo com a conta) + token assinado da URL
  (`attachment_id`/`blob_id`/`user_id`/`account_id`/`epoch`, expiração 5 min) + Gate de leitura
  `attachment_download`; sem token/conta/epoch válidos responde 404 sem vazar bytes.
  Fontes: `attachment_downloads_controller.rb:9-18` (show + Gate), `:25-39` (verify_token),
  `attachment_token.rb:7-8` (PURPOSE/TTL) e `:10-18` (issue), `attachment_url_hook.rb:47-49` (helper da rota).
- 877 nativas preservadas: nenhum `controller`/`prefix`/`path` existente foi tocado; só adicionada a superfície
  do controller novo. Sem `mandatory_actions`/`mandatory_paths` novos (a rota do spike só existe com o
  Installer instalado nos specs G0; o inventário roda sobre `Rails.application.routes` como antes).

## 3. AC2 — ofensas próprias corrigidas/justificadas (expectativas preservadas)

- `attachment_download_scope_spec.rb` (14 → 0):
  - `BODY`/`IMAGE_PATH` (ConstantDefinitionInBlock + LeakyConstantDeclaration ×2 pares): viraram
    `stub_const` em `before` (mesmos nome/valor/uso). Sem `stub_const('Attachment::BODY')`: o cop
    `RSpec/LeakyConstantDeclaration` reclama de constante declarada no bloco mesmo com namespace.
  - `@image_attachment`/`@control_attachment` (InstanceVariable ×9): viraram locais por exemplo com
    `ensure` de deleção do blob. O `after` global passou a limpar só o `attachment` de série
    (único compartilhado entre exemplos); cada exemplo limpa o seu local no próprio `ensure`.
    Preservado: nenhum exemplo elimina limpeza; contagem/efeito/autorização intactos.
- `scope_b1_leftovers_spec.rb` (17 → 0):
  - `MultipleMemoizedHelpers` (13×, grupo com 16 helpers vs Max 14 do `.rubocop.yml:204-205`):
    disable em par de arquivo (`disable` no topo + `enable` no fim) com justificativa curta —
    quebrar o grupo exigiria mover exemplos entre arquivos e reduziria a clareza da matriz B1,
    sem mudar autorização/contagem/efeito.
  - `LetSetup` (`incoming_a` nunca referenciado): `let!` removido; criação equivalente movida para
    o `before` existente (side-effect preservado, ordem mantida).
  - `AmbiguousBlockAssociation` ×2: auto-fix `-a` parentetizou `change { ... }` → `change(...)`.
  - `HashAlignment` ×1: auto-fix `-a` realinhou `as: :json`.
  - `EmptyLineAfterFinalLet` ×1 (apareceu após mover o setup para o `before`): linha em branco manual.
- `scope_team_contact_spec.rb` (10 → 0):
  - `MultipleDescribes` (2 grupos de topo): disable em par de arquivo com justificativa curta —
    unir request + listener reduziria a clareza (contratos distintos), sem mudar autorização/contagem/efeito.
  - `SpecFilePathFormat`: o fix da C removeu o disable redundante (trocado por comentário simples no lugar).
  - `WhereExists`: `where(...).exists?` → `exists?(...)` (mesma consulta).
  - `HashAlignment` ×1: auto-fix `-a` realinhou.
  - `RedundantConstantBase` ×4: auto-fix `-a` removeu `::` (`ActionCableListener < BaseListener` já resolve
    `ContactInbox` no top-level; sem classe aninhada — verificado em `app/listeners/action_cable_listener.rb:1`).
  - `ContainExactly` ×2 com splat: viraram `match_array(snapshot_tokens)` (ordem irrelevante, mesmo conjunto).
- `captain_scope_spec.rb` (1 → 0): `HashAlignment` via auto-fix `-a` (realinhamento de `headers:`/`as:`).
- `route_inventory_spec.rb` (0 → 0): só a superfície nova (AC1); nenhum fix de lint necessário.
- RuboCop `-a` usado SOMENTE nos 5 arquivos próprios, escopo `Layout,Style,Rails,Lint/AmbiguousBlockAssociation`
  (sem `-A`, sem varredura G0, sem app). Nenhum disable global/all, nenhuma autorização enfraquecida.

## 4. AC3 — RuboCop check próprio + logs (nenhum teste funcional executado)

- Check final (exit 0), `env -i` + Ruby 3.4.4 + BUNDLE_* do launcher (receita `gotchas.md:43`):
  ```sh
  env -i PATH=/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin:/usr/bin:/bin HOME="$HOME" LANG=C.UTF-8 BUNDLE_GEMFILE=/home/thanos/chatwootnext-connecta-g0-prep/Gemfile BUNDLE_PATH=/home/thanos/chatwootnext-connecta-g0-prep/.bundle/gems BUNDLE_FROZEN=true bundle exec rubocop --format json --out .context/evidence/g0/31-logs/spec-lint.json spec/connecta/attachment_download_scope_spec.rb spec/connecta/scope_b1_leftovers_spec.rb spec/connecta/scope_team_contact_spec.rb spec/connecta/captain_scope_spec.rb spec/requests/connecta/route_inventory_spec.rb
  ```
  INICIO_UTC 2026-10-24T18:26:53Z, FIM_UTC 2026-10-24T18:26:54Z, duração real 1 s, RuboCop 1.75.6.
  **5 arquivos, 0 ofensas**, EXIT 0, stderr vazio.
- JSON: `31-logs/spec-lint.json`. Run log: `31-logs/spec-lint.log` (INICIO/EXIT/DURACAO/FIM). stderr: `31-logs/spec-lint.stderr.log` (vazio).
- `ruby -c` 3.4.4 nos 5 alterados: `Syntax OK` ×5.
- `git diff --check` (rastreado): limpo. Não rastreados read-only
  `git diff --no-index --check /dev/null <arquivo>`: exit 1 + **sem saída** nos 5 (sem warning de whitespace;
  exit 1 aqui só diz que há diff contra /dev/null — semântica registrada em `29-regressao-lint.md` §6).
- `git status --short`: só os 7 grupos `??` pré-existentes (nenhum rastreado modificado, sem commit).
- `df -h /tmp`: tmpfs 7,6 GB, 5,1 GB usados, 67% (leitura, sem apagar).
- Nenhum `rspec`, build ou teste funcional executado nesta tarefa.
