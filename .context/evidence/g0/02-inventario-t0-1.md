# G0 — inventário de rotas T0.1 (resultado real)

- Spec: `spec/requests/connecta/route_inventory_spec.rb` (guarda: `spec/support/connecta/g0_target_guard.rb`).
- Execução: `scripts/connecta/g0_test_env.sh --spec --apply`, alvo G0 (banco `conecta_baileys_g0_test`), 2026-10-22.
- Resultado final: exit 0, `3 examples, 0 failures` (classificação, superfícies obrigatórias, catch-all do SPA).
- Primeira execução: exit 1, `3 examples, 1 failure` (22 rotas sem superfície). Ver seção "Rotas reclassificadas".
- Escopo: classificação por área (controller, prefixo, caminho). **Não valida a matriz §10.1 literal**: o plano externo não foi lido nesta entrega (ver `PROJECT_STATE.md`). Não prova EVID2..8.

## Contagens (hook somente leitura, após a correção)

- Rotas no total (`Rails.application.routes.routes`, achatadas): **877**.
- Não classificadas: **0**.
- Infraestrutura (`infra`): **11**.
- Rotas que caem em mais de uma superfície: **7** (ex.: `/` está em "URL do browser" e em "canais externos").

Classificações por superfície (uma rota pode aparecer em mais de uma):

| Superfície | Rotas | Fronteira (resumo; texto completo na spec) |
|---|---:|---|
| conversas e sub-recursos | 60 | `Api::BaseController` + vínculo com a conta |
| URL do browser (SPA) | 25 | `DashboardController` sem auth própria; dados vêm das APIs |
| busca | 5 | `Api::BaseController` |
| anexos, proxies, blobs e uploads | 12 | ActiveStorage (URL assinada); Slack sem usuário, só chave aleatória do blob |
| contatos, empresas, grupos, importação/exportação | 68 | `Api::BaseController` + vínculo com a conta |
| deduplicação de contatos | 1 | `Api::BaseController` + vínculo |
| ações em lote | 2 | `Api::BaseController` + vínculo |
| filtros salvos | 6 | `Api::BaseController` |
| notificações | 14 | `Api::BaseController`; push por usuário |
| relatórios, exportações, SLA e auditoria | 29 | `Api::BaseController`; relatórios v2 exigem administrador |
| CSAT | 13 | conta autenticada; página pública sem autenticação (identificada só pelo UUID) |
| integrações, apps, webhooks e callbacks | 51 | `Api::BaseController`; hooks com `check_authorization` |
| automações, macros, campanhas, respostas prontas | 25 | `Api::BaseController` + vínculo |
| Captain (IA) | 68 | `Api::BaseController` + vínculo |
| chat interno | 39 | `Api::BaseController` + vínculo |
| caixas, canais, QR/status, OAuth e chamadas | 48 | `Api::BaseController`; QR/sessão/saúde via `fetch_inbox` → `authorize show?` |
| sockets (ActionCable) | 1 | sem autenticação na conexão; `RoomChannel` por `pubsub_token` |
| widget | 27 | token do widget; contato por JWT HS256 (`X-Auth-Token`) |
| API pública de inbox e portais de ajuda | 36 | `PublicController`; caixa por `identifier`; HMAC só para contatos |
| portais de ajuda (gestão) | 34 | `Api::BaseController` |
| conta e administração | 85 | `Api::V1::Accounts::BaseController`; papel por Pundit |
| autenticação e perfil | 47 | Devise Token Auth; `/auth/:provider` (redirect) |
| canais externos (webhooks, OAuth, verificação) | 44 | validação de assinatura por canal; `/` = engine AWS SES (ver abaixo) |
| plataforma | 24 | token de plataforma |
| super admin, instalação e monitoramento | 92 | Devise super_admin; Sidekiq::Web sob `authenticated :super_admin` |
| cobrança Enterprise e webhooks de pagamento | 17 | `Api::BaseController` (Enterprise) |
| **infraestrutura** (`infra`) | 11 | `api`, `health`, `manifest`, … e `/assets` (Sprockets) |

## Rotas reclassificadas nesta execução (22)

Não havia superfície nas regras anteriores porque são montagens ou rotas sem controller da aplicação, ou rotas Devise padrão do super admin. Cada uma recebeu fronteira verificada:

| Rota | Origem verificada | Superfície |
|---|---|---|
| `/assets` (mount) | sprockets-rails 3.4.2, `lib/sprockets/railtie.rb:224-225` | infraestrutura (`paths`) |
| `GET\|POST /auth/:provider` (redirect) | devise_token_auth 1.2.5, `lib/devise_token_auth/rails/routes.rb:76-90`; sem `redirect_whitelist` em `config/initializers/devise_token_auth.rb` | autenticação e perfil (`paths`) |
| `GET /super_admin/password/new`, `GET /super_admin/password/edit`, `PATCH\|PUT\|POST /super_admin/password` (5 rotas) | `config/routes.rb:769`; `app/models/super_admin.rb:48` (`< User`); `app/models/user.rb:60-69` (recoverable) | super admin (`controllers: devise/passwords`) |
| `GET /super_admin/cancel`, `GET /super_admin/sign_up`, `GET /super_admin/edit`, `PATCH\|PUT\|DELETE\|POST /super_admin` (7 rotas) | idem; registerable | super admin (`controllers: devise/registrations`) |
| `GET /super_admin/confirmation/new`, `GET\|POST /super_admin/confirmation` (3 rotas) | idem; confirmable | super admin (`controllers: devise/confirmations`) |
| `GET\|POST /omniauth/google_oauth2`, `…/callback`, `GET\|POST /omniauth/saml`, `…/callback` (4 rotas) | nomes `super_admin_*_omniauth_*`; `app/models/user.rb:69` (`omniauthable`, providers `google_oauth2`, `saml`) | super admin (`controllers: devise/omniauth_callbacks`) |
| `/` (mount do engine `aws_action_mailbox_ses_engine`) | gem `aws-actionmailbox-ses` 0.1.0, `lib/aws/action_mailbox/ses/engine.rb:13-15`; `POST /ses/inbound_emails` responde 401 sem assinatura SNS válida, `app/controllers/action_mailbox/ingresses/ses/inbound_emails_controller.rb:47` | canais externos (`paths: /`) |

Total: 1 + 1 + 5 + 7 + 3 + 4 + 1 = **22**.

## Riscos abertos (não corrigidos: autenticação da aplicação está fora de escopo)

1. **Super admin com rotas Devise públicas.** `SuperAdmin < User` herda `registerable`, `recoverable`, `confirmable` e `omniauthable`. As rotas `POST /super_admin` (cadastro), de recuperação de senha e de confirmação aparecem com controllers Devise padrão. No código lido, não há `before_action` de autenticação em `app/controllers/application_controller.rb:8-10` (só `verify_authenticity_token` pulado e `set_current_user`), e `config/initializers/devise.rb` não define `parent_controller`. **Não verificado em runtime**: falta um request de teste (a ser autorizado) para confirmar se a resposta é aceita sem credencial. Não há conclusão de vulnerabilidade sem essa prova.
2. **`/auth/:provider` sem whitelist de redirect.** `config/initializers/devise_token_auth.rb` não define `redirect_whitelist`; a checagem de `auth_origin_url` em `routes.rb:89` só roda com whitelist configurada. Não verificado o efeito no callback.
3. **Canais sem validação de assinatura** já registrados em `PROJECT_STATE.md` (Twitter/X POST, Telegram, SMS, Twilio). Não alterados aqui.
