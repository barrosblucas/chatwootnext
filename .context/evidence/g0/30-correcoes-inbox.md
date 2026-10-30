# 30 — Correção: gate de autorização da inbox física (G0, TASK_ID g0-fix-inbox-regression)

SOMENTE diagnóstico de causa + correção de código. NENHUM SPEC EXECUTADO nesta tarefa
(outras frentes em mutação; instrução do briefing). Prova funcional PENDENTE em
validação consolidada posterior. Sem transporte real. Sem core.

## 1. Falhas-alvo (log `29-logs/g2-lote-1.log`, expectativas em `spec/connecta/scope_related_http_spec.rb:368-398`)

| # | Spec (linha) | Ator/ação | Esperado | Obtido | Sintoma |
|---|---|---|---|---|---|
| 1 | `:368` (asserção `:371`) | agente com membership → `POST setup_channel_provider` | 403 + 0 transporte | 500 | Gate ausente: chegou ao provedor Baileys (HTTParty bloqueado pelo WebMock → erro mascarado como 500) |
| 2 | `:375` (asserção `:378`) | gestor → `POST import_whatsapp_session` | 403 + 0 transporte | 422 `:unprocessable_content` | Gate ausente: validação nativa de payload/canal respondeu antes da negação |
| 3 | `:382` (asserção `:385`) | agente → `GET health` | 404 + 0 transporte | 400 | Gate ausente: `validate_whatsapp_cloud_channel` respondeu antes da negação |
| 4 | `:389` (asserção `:392`) | agente → `POST on_whatsapp` | 403 + 0 transporte | 500 | Gate ausente: chegou ao provedor (WebMock → 500 mascarado) |
| 5 | `:396` (asserção `:398`) | agente → `PATCH/DELETE` inbox | 403 + nome intacto/sem job | 401 do Pundit nativo | Gate ausente: sem negação própria; caiu na autorização nativa (401), que não é o contrato do spike |

A 6ª falha do lote (`route_inventory_spec.rb:204`, rota nova `connecta_attachments#show`
não classificada) é de OUTRA frente (B) — NÃO tocada aqui.

## 2. Causa real (leitura do código, sem varrer o G0)

`app/services/connecta/scope/inbox_hook.rb` (`fetch_inbox`, prepended no
`InboxesController`): na versão quebrada o hook SÓ agendava auditoria pendente
para ações em `NOMINAL_ACTIONS`, sem negar nada. Consequência:

- Ações SEM `check_authorization` nativo (`setup_channel_provider`,
  `import_whatsapp_session`, `health`, `on_whatsapp` — ver
  `app/controllers/api/v1/accounts/inboxes_controller.rb:7` + concern
  `whatsapp_health_management.rb:7`): nenhum gate rodava → validação de
  payload/canal ou chamada HTTParty ao Baileys rodava primeiro (500/422/400).
- Ações COM `check_authorization` nativo (`update`, `destroy`): caíam no 401 do
  Pundit (`InboxPolicy#update?/destroy?` exigem `administrator?`; fixture dá
  `role: :agent` a todos — `g0_scope_fixture.rb:20-24`), sem a negação 403
  própria do spike.

O bypass NÃO concedeu acesso: agente/gestor/membro nunca executaram efeito —
mas o CONTRATO (403/404 antes de validação/provedor, 0 transporte) foi violado.

## 3. Correção (só `inbox_hook.rb`, sem core, sem tocar em specs)

`fetch_inbox` agora é o gate (roda após autenticação/conta carregadas, ANTES da
validação nativa de payload e de qualquer chamada ao provedor), SOMENTE para
inbox marcada + ação em `NOMINAL_ACTIONS`:

- Não-admin nominal (`Projection#admin?` falso — agente/gestor/membro): grava
  `AccessAudit` `deny` (`surface: inbox`, `access_path: inbox_<ação>`) e levanta
  `Connecta::Scope::Denied` (`:not_found` em GET, `:forbidden` nas demais) →
  renderizado pelo `rescue_from(Denied)` do installer. Nenhum transporte é
  tocado (o `raise` sai antes do corpo da ação). Cobre os 5 casos:
  `setup_channel_provider`, `import_whatsapp_session`, `health` (GET → 404),
  `on_whatsapp`, `update`/`destroy`.
- Admin nominal: NÃO nega aqui; agenda a auditoria pendente e segue o fluxo
  nativo (autenticação/autorização nativas intactas). `check_authorization` /
  `check_admin_authorization?` (override novo, cobre `register_webhook` — única
  ação nominal sob `check_admin_authorization?`) fazem `super` primeiro e SÓ com
  `super` sem exceção convertem o pendente em `allow` (`inbox_<ação>`); com
  `Pundit::NotAuthorizedError` o pendente é descartado e o 401 nativo segue —
  correção c7b preservada (sem `allow` fantasma; `b2_complements_spec.rb:117`
  continua verde).
- Inbox NÃO marcada: retorno antes do gate → 100% nativo (positivo
  `on_whatsapp` 422 de canal não suportado em `scope_related_http_spec.rb:424`
  preservado). `show`/campanhas/GET fora de `NOMINAL_ACTIONS` seguem nativos sem
  auditoria (caracterização da evidência 15, sem mudança). `create` WhatsApp
  segue no guard próprio `prepend_before_action` (inalterado).
- Nenhum acesso novo concedido: o gate SÓ nega não-nominais; nominais seguem o
  nativo como antes.

Diff (arquivo novo untracked — `git diff` de rastreados não mostra; leitura via
`Read`): `fetch_inbox` (+gate deny / +pending só nominal), `+check_admin_authorization?`
(flush/descarte simétrico), resto idêntico. `installer.rb` NÃO alterado
(`rescue_from(Denied)` já cobre o `InboxesController`; `fetch_inbox` prepended
já roda antes dos `before_action` de validação).

## 4. AC1/AC2 (por que atendem, sem alegar teste verde)

- AC1 (gate antes de efeito/validação/provedor; nada novo concedido): §3 — o
  `raise Denied` no `fetch_inbox` precede TODA a lógica da ação (validação de
  payload, `validate_whatsapp_cloud_channel`, HTTParty Baileys, `update!`,
  `DeleteObjectJob`). WebMock `a_request(:any, /.*/)` continua sem chamada nos
  5 casos.
- AC2 (nativa/admin auditado/unmarked preservados): nominais passam pelo nativo
  (`token_admin` pareia em `:415-421` — Baileys stubado UMA vez, 200 + transporte
  chamado); `allow` só pós-autorização (c7b intacto); unmarked retorna antes do
  gate; `owner_nominal` (admin conta + grant, `b2_complements:108-114`) ainda
  recebe 200 + `allow` em `inbox_update` (caminho: nominal → pendente → `super`
  ok → flush). `token_owner` NÃO é afetado pelo gate (é nominal).
- AC3 (causa/correção/casos + execução pendente): este arquivo. Execução
  pendente explícita no §5.

## 5. Execução pendente (NÃO executada aqui — código global em mutação)

Na validação consolidada (com fila, launcher 300 s), rodar SOMENTE:

```sh
scripts/connecta/g0_test_env.sh --spec --apply spec/connecta/scope_related_http_spec.rb
```

Esperado: `:368/:375/:389/:396` → 403 + 0 transporte; `:382` → 404 + 0
transporte; `:407` (agente cria WhatsApp → 403) e `:415` (admin pareia → 200 +
transporte 1×) e `:424` (unmarked 422) e demais casos do arquivo sem mudança.
NÃO rodar outros specs/lint/build nesta frente.

## 6. Validação DESTA tarefa (sem specs, sem lint de outros módulos)

- `/home/thanos/.cache/connecta-g0-test/toolchain/mise-data/installs/ruby/3.4.4/bin/ruby -c app/services/connecta/scope/inbox_hook.rb` → `Syntax OK`.
- `git diff --check` (rastreados) → limpo, exit 0.
- `git diff --no-index --check /dev/null app/services/connecta/scope/inbox_hook.rb` → sem saída (exit 1 = há diff novo, sem warning de whitespace).
- `git status --short` → só os 7 grupos `??` pré-existentes (nenhum rastreado modificado; este Coder não dá `git add`).
- `df -h /tmp` → leitura, sem apagar (tmpfs 7.6G, 67% usado no momento da checagem).
- Specs/rubocop/build NÃO executados (briefing: outras frentes em mutação).
