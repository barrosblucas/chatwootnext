require_relative '../../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

# Inventário provisório da matriz §10.1 (Connecta/Baileys). Lê as rotas que o app realmente desenha.
# Classificação por área (controller) e por caminho; a fronteira de autenticação é registrada em cada superfície.
# Não valida a matriz literal: o plano externo não foi lido nesta entrega (ver .context/PROJECT_STATE.md).
RSpec.describe 'Connecta route inventory' do
  let(:routes) do
    Rails.application.routes.routes.map do |route|
      {
        verb: route.verb,
        path: route.path.spec.to_s.delete_suffix('(.:format)'),
        controller: route.defaults[:controller],
        action: route.defaults[:action]
      }
    end
  end

  # Superfícies de dados. Uma rota é classificada quando cai em `controllers`, em `prefixes` (área, com "/" como fronteira) ou em `paths`.
  let(:surfaces) do
    {
      'conversas e sub-recursos (mensagens, anexos, agendadas, rótulos, participantes, transferência)' => {
        auth: 'conta: Api::BaseController (token de acesso ou Devise) + vínculo com a conta',
        prefixes: %w[api/v1/accounts/conversations]
      },
      'URL do browser (SPA catch-all, rotas de e-mail e página de widget)' => {
        auth: 'SPA: DashboardController (ActionController::Base) sem auth própria; dados vêm das APIs',
        controllers: %w[dashboard apps accounts conversations widgets],
        paths: %w[/app/*params]
      },
      'busca' => { auth: 'conta: Api::BaseController', prefixes: %w[api/v1/accounts/search] },
      'anexos, proxies, blobs e uploads' => {
        auth: 'ActiveStorage: URL assinada (signed_id); Slack: SlackUploadsController sem autenticação de usuário, ' \
              'só a chave aleatória do blob (slack_uploads_controller.rb:1,15-17)',
        prefixes: %w[active_storage api/v1/accounts/upload api/v1/accounts/contacts/attachments slack_uploads]
      },
      'contatos, empresas, grupos e importação/exportação' => {
        auth: 'conta: Api::BaseController + vínculo com a conta',
        prefixes: %w[api/v1/accounts/contacts api/v1/accounts/companies api/v1/accounts/groups
                     api/v1/accounts/contact_inboxes api/v1/accounts/data_imports]
      },
      'deduplicação de contatos (contact merge)' => {
        auth: 'conta: Api::BaseController + vínculo com a conta',
        prefixes: %w[api/v1/accounts/actions]
      },
      'ações em lote' => {
        auth: 'conta: Api::BaseController + vínculo com a conta',
        prefixes: %w[api/v1/accounts/bulk_actions api/v1/accounts/captain/bulk_actions]
      },
      'filtros salvos' => { auth: 'conta: Api::BaseController', prefixes: %w[api/v1/accounts/custom_filters] },
      'notificações' => {
        auth: 'conta: Api::BaseController; push: api/v1/notification_subscriptions (conta do usuário)',
        prefixes: %w[api/v1/accounts/notifications api/v1/accounts/notification_settings api/v1/notification_subscriptions]
      },
      'relatórios, exportações, SLA e auditoria' => {
        auth: 'conta: Api::BaseController (api/base_controller.rb:4-6); relatórios v2: ReportPolicy#view? exige administrador ' \
              '(reports_controller.rb:105-107; report_policy.rb:2-4); outras ações: policy por ação, não auditada aqui',
        prefixes: %w[api/v2/accounts api/v1/accounts/reporting_events api/v1/accounts/applied_slas api/v1/accounts/audit_logs]
      },
      'CSAT (conta, página pública e pesquisa)' => {
        auth: 'conta: Api::BaseController; pública: PublicController (ActionController::Base, public_controller.rb:3-5) sem autenticação; ' \
              'a conversa é identificada só pelo UUID em :id (public/api/v1/csat_survey_controller.rb:18), sem HMAC nem token; ' \
              'update aceito em até 14 dias (:8,29-31); Survey::ResponsesController (ActionController::Base)',
        prefixes: %w[api/v1/accounts/csat_survey_responses api/v1/accounts/inbox_csat_templates public/api/v1/csat_survey survey/responses]
      },
      'integrações, apps, webhooks e callbacks da conta' => {
        auth: 'conta: Api::BaseController; hooks: check_authorization em todas as ações (hooks_controller.rb:3) → HookPolicy ' \
              '(integrations/base_controller.rb:6-7); callbacks OAuth de provedores ficam na superfície de canais externos',
        prefixes: %w[api/v1/accounts/integrations api/v1/accounts/webhooks api/v1/accounts/dashboard_apps
                     api/v1/accounts/callbacks api/v1/accounts/agent_bots]
      },
      'automações, macros, campanhas e respostas prontas' => {
        auth: 'conta: Api::BaseController + vínculo com a conta',
        prefixes: %w[api/v1/accounts/automation_rules api/v1/accounts/macros api/v1/accounts/campaigns api/v1/accounts/canned_responses]
      },
      'Captain (IA)' => { auth: 'conta: Api::BaseController + vínculo com a conta', prefixes: %w[api/v1/accounts/captain] },
      'chat interno' => { auth: 'conta: Api::BaseController + vínculo com a conta', prefixes: %w[api/v1/accounts/internal_chat] },
      'caixas, canais, QR/status, OAuth e chamadas' => {
        auth: 'conta: Api::BaseController; QR, sessão e saúde passam por fetch_inbox → authorize show? (inboxes_controller.rb:3,178-180)',
        prefixes: %w[api/v1/accounts/inboxes api/v1/accounts/conference api/v1/accounts/inbox_members api/v1/accounts/channels api/v1/accounts/calls
                     api/v1/accounts/whatsapp_calls api/v1/accounts/twitter api/v1/accounts/microsoft api/v1/accounts/google
                     api/v1/accounts/instagram api/v1/accounts/tiktok api/v1/accounts/notion api/v1/accounts/whatsapp]
      },
      'sockets (ActionCable)' => {
        auth: 'sem autenticação na conexão (application_cable/connection.rb:1-2); RoomChannel#subscribed identifica por ' \
              'pubsub_token (room_channel.rb:42-48); conta por membership (room_channel.rb:56) ou contato (room_channel.rb:54)',
        paths: %w[/cable]
      },
      'widget (canal público por token do widget)' => {
        auth: 'widget: Api::V1::Widget::BaseController < ApplicationController, sem authenticate_user! (application_controller.rb:10,16-19); ' \
              'website_token só identifica a caixa (concerns/website_token_helper.rb:6-7). Autenticação do contato: X-Auth-Token é JWT HS256 ' \
              'assinado com secret_key_base (concerns/website_token_helper.rb:3; services/base_token_service.rb:9,20-26); sem token válido, ' \
              'set_contact levanta RecordNotFound (website_token_helper.rb:13-18). Identificação: identifier, sem verificação quando não há ' \
              'identifier_hash e a caixa não é hmac_mandatory. HMAC-SHA256 do identifier com hmac_token ' \
              '(api/v1/widget/contacts_controller.rb:4-5,66-85)',
        prefixes: %w[api/v1/widget widgets]
      },
      'API pública de inbox e portais de ajuda' => {
        auth: 'público: PublicController (public_controller.rb:3), sem Devise; caixa por identifier (inboxes_controller.rb:12-15) ' \
              'e contato por source_id. Contatos (inboxes/contacts_controller.rb:3,31-33): HMAC só se hmac_mandatory ou identifier_hash ' \
              '(:32). Mensagens (inboxes/messages_controller.rb:1,8-12): sem HMAC; herdam inboxes_controller.rb:2-4, e ' \
              'hmac_verified só escolhe o escopo da conversa (inboxes_controller.rb:27-31)',
        prefixes: %w[public/api/v1]
      },
      'portais de ajuda (gestão na conta, categorias e artigos)' => {
        auth: 'conta: Api::BaseController',
        prefixes: %w[api/v1/accounts/portals api/v1/accounts/categories api/v1/accounts/articles]
      },
      'conta e administração (conta, agentes, equipes, políticas, rótulos, atributos, SAML, onboarding)' => {
        auth: 'conta: Api::V1::Accounts::BaseController < Api::BaseController (accounts/base_controller.rb:1,4-5); ' \
              'papel por ação via Pundit (policy de cada controller; não auditada item a item nesta classificação)',
        controllers: %w[api/v1/accounts],
        prefixes: %w[api/v1/accounts/agents api/v1/accounts/teams api/v1/accounts/team_members api/v1/accounts/custom_roles
                     api/v1/accounts/sla_policies api/v1/accounts/agent_capacity_policies api/v1/accounts/assignment_policies
                     api/v1/accounts/assignable_agents api/v1/accounts/labels api/v1/accounts/custom_attribute_definitions
                     api/v1/accounts/branded_email_layouts api/v1/accounts/onboardings api/v1/accounts/saml_settings
                     api/v1/accounts/redirect_tokens]
      },
      'autenticação e perfil (Devise Token Auth, MFA, sessões e assinaturas)' => {
        auth: 'Devise Token Auth (fronteira própria, sem token de conta); perfil: usuário autenticado; ' \
              '/auth/:provider é redirect sem controller (gem devise_token_auth 1.2.5, rails/routes.rb:76-90); ' \
              'sem redirect_whitelist configurada (config/initializers/devise_token_auth.rb), auth_origin_url não é validada nessa rota',
        prefixes: %w[devise_token_auth devise_overrides auth api/v1/auth api/v1/profiles api/v1/profile],
        paths: %w[/auth/:provider]
      },
      'canais externos: webhooks de entrada, callbacks OAuth e verificação' => {
        auth: 'sem usuário (webhooks_controller.rb:2). Com validação: WhatsApp e Instagram (verify_meta_signature!, ' \
              'whatsapp_controller.rb:4, instagram_controller.rb:4), TikTok (tiktok_controller.rb:2), Shopify (shopify_controller.rb:2), ' \
              'Line (line_events_job.rb:7), Stripe (stripe_controller.rb:9), Firecrawl (firecrawl_controller.rb:18-20). ' \
              'Sem validação de assinatura no código: Twitter/X POST (webhooks_controller.rb:9-15), Telegram (bot_token na URL; ' \
              'telegram_controller.rb:2), SMS (sms_controller.rb:2), Twilio callback e status (twilio/callback_controller.rb:2, ' \
              'twilio/delivery_status_controller.rb:2) e voz Enterprise (twilio/voice_controller.rb:9); ' \
              'rota "/" é o engine AWS SES (gem aws-actionmailbox-ses 0.1.0, lib/aws/action_mailbox/ses/engine.rb:13-15): ' \
              'POST /ses/inbound_emails responde 401 sem assinatura SNS válida ' \
              '(app/controllers/action_mailbox/ingresses/ses/inbound_emails_controller.rb:47 da gem)',
        prefixes: %w[webhooks api/v1/webhooks api/v1/integrations/webhooks twitter/callbacks linear/callbacks shopify/callbacks
                     twilio microsoft/callbacks google/callbacks instagram/callbacks tiktok/callbacks notion/callbacks
                     action_mailbox rails/conductor],
        paths: %w[/bot /]
      },
      'plataforma (token de plataforma)' => { auth: 'PlatformController (token de plataforma)', prefixes: %w[platform/api/v1] },
      'super admin, instalação e monitoramento' => {
        auth: 'Devise super_admin (routes.rb:769-770); SuperAdmin < User (app/models/super_admin.rb:48) herda registerable, ' \
              'recoverable, confirmable e omniauthable (app/models/user.rb:60-69); controllers Devise padrão, sem override ' \
              '(devise/passwords, devise/registrations, devise/confirmations, devise/omniauth_callbacks); sem before_action de ' \
              'autenticação em application_controller.rb:8-10; Sidekiq::Web sob authenticated :super_admin (routes.rb:805-806)',
        prefixes: %w[super_admin installation],
        controllers: %w[devise/passwords devise/registrations devise/confirmations devise/omniauth_callbacks],
        paths: %w[/monitoring/sidekiq]
      },
      'cobrança Enterprise e webhooks de pagamento' => {
        auth: 'enterprise/api/v1/accounts_controller.rb:1 herda Api::BaseController; webhooks de pagamento: ver canais externos',
        prefixes: %w[enterprise]
      }
    }
  end

  # Infraestrutura sem dados de conta, conversa, contato ou canal. /assets é o Sprockets (gem sprockets-rails 3.4.2, railtie.rb:224-225).
  let(:infra) do
    { controllers: %w[api health manifest android_app apple_app microsoft custom_domains swagger widget_tests], paths: %w[/assets] }
  end

  # Superfícies obrigatórias: ao menos uma rota com este controller#action precisa existir.
  let(:mandatory_actions) do
    {
      'conversa: lista' => ['api/v1/accounts/conversations', 'index'],
      'mensagem: criação' => ['api/v1/accounts/conversations/messages', 'create'],
      'mensagens agendadas' => ['api/v1/accounts/conversations/scheduled_messages', 'index'],
      'mensagens recorrentes' => ['api/v1/accounts/conversations/recurring_scheduled_messages', 'index'],
      'anexo: upload direto' => ['api/v1/accounts/conversations/direct_uploads', 'create'],
      'anexo: proxy de blob' => ['active_storage/blobs/proxy', 'show'],
      'contato: exportação' => ['api/v1/accounts/contacts', 'export'],
      'deduplicação de contatos' => ['api/v1/accounts/actions/contact_merges', 'create'],
      'ações em lote' => ['api/v1/accounts/bulk_actions', 'create'],
      'filtros salvos' => ['api/v1/accounts/custom_filters', 'index'],
      'notificações' => ['api/v1/accounts/notifications', 'index'],
      'relatórios' => ['api/v2/accounts/reports', 'index'],
      'exportação de CSAT' => ['api/v1/accounts/csat_survey_responses', 'download'],
      'integração: hooks' => ['api/v1/accounts/integrations/hooks', 'create'],
      'automação' => ['api/v1/accounts/automation_rules', 'index'],
      'Captain' => ['api/v1/accounts/captain/assistants', 'index'],
      'chat interno: mensagem' => ['api/v1/accounts/internal_chat/messages', 'create'],
      'QR/status: setup do canal' => ['api/v1/accounts/inboxes', 'setup_channel_provider'],
      'QR/status: sessão importada' => ['api/v1/accounts/inboxes', 'import_whatsapp_session'],
      'QR/status: health' => ['api/v1/accounts/inboxes', 'health'],
      'widget: mensagem' => ['api/v1/widget/messages', 'create'],
      'público: mensagem de inbox' => ['public/api/v1/inboxes/messages', 'create']
    }
  end

  # Caminhos obrigatórios, com o controller esperado (nil para mounts sem controller).
  let(:mandatory_paths) { { '/cable' => nil, '/app/*params' => 'dashboard' } }

  let(:matches) do
    lambda do |route, rules|
      controller = route[:controller].to_s
      Array(rules[:controllers]).include?(controller) ||
        Array(rules[:prefixes]).any? { |prefix| controller == prefix || controller.start_with?("#{prefix}/") } ||
        Array(rules[:paths]).include?(route[:path])
    end
  end

  it 'classifies every route as a surface or as infrastructure' do
    unclassified = routes.reject do |route|
      surfaces.values.any? { |rules| matches.call(route, rules) } || matches.call(route, infra)
    end

    expect(unclassified.map { |route| "#{route[:verb]} #{route[:path]} (#{route[:controller] || 'mount'}##{route[:action]})" }.uniq).to be_empty
  end

  it 'exposes every mandatory surface, including sockets, QR/status and the SPA catch-all' do
    missing_actions = mandatory_actions.reject do |_name, (controller, action)|
      routes.any? { |route| route[:controller] == controller && route[:action] == action }
    end
    missing_paths = mandatory_paths.reject do |path, controller|
      routes.any? { |route| route[:path] == path && route[:controller] == controller }
    end

    expect(missing_actions.keys + missing_paths.keys).to be_empty
  end

  it 'serves the conversation URL through the SPA catch-all, not the nested conversations route' do
    expect(Rails.application.routes.recognize_path('/app/accounts/1/conversations/2', method: :get))
      .to include(controller: 'dashboard', action: 'index')
  end
end
