require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF4 entrega pendente (spike G0, rev. 2, bloco B3): jobs nativos de push/email
# serializados, com revogacao/transferencia/epoch revalidados na execucao.
# Casos ESCRITOS e NAO EXECUTADOS; B1b/B2 implementam binding/guard em runtime
# (plano rev. 2, l. 157-165). Somente API publica nativa: create(:notification),
# enqueued_jobs, JSON round-trip, ActiveJob::Base.execute, ORM fixtures.
# Nenhum helper novo da infra; nenhum Gate/Finder/Controller stubado; sem M2
# final (MailDeliveryJob pendente) nem socket RF5 neste arquivo. Execucao real
# pendente na validacao consolidada (Bloco D); RF4 NAO validado aqui.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Casos B3 juntam push+email+serializacao por caso (AC1/AC2); expectativas
# agrupadas por caso para manter a suite focada (<= 15 min de execucao).
RSpec.describe 'Connecta G0 · entrega pendente de notificacao (RF4/B3)', type: :request do
  include_context 'with connecta g0 scope fixture'

  # config/initializers/mailer.rb troca para :sendmail quando SMTP_ADDRESS está vazio (o runner usa env -i).
  # Este spec prova o fluxo sem entrega real: fixa :test e restaura ao fim.
  let!(:previous_delivery_method) { ActionMailer::Base.delivery_method }

  before do
    ActionMailer::Base.delivery_method = :test
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
    allow(WebPush).to receive(:payload_send).and_return(true)
    [agent_a, agent_b, manager_a, member_without_grant, admin_nominal].each do |user|
      user.notification_settings.find_by(account_id: account.id).update!(
        selected_email_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"email_#{type}" },
        selected_push_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"push_#{type}" }
      )
      user.update!(confirmed_at: Time.current) if user.confirmed_at.nil?
    end
    # Boundary fake valida: subscription browser_push real para A, de modo que
    # 0 push nos negativos nao passe so por falta de subscription. Tipo
    # conversation_assignment nao consulta OnlineStatusTracker no mailer, de modo
    # que 0 email nos negativos nao passe so por usuario online.
    create(:notification_subscription, :browser_push, user: agent_a)
  end

  after do
    ActionMailer::Base.delivery_method = previous_delivery_method
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
  end

  def create_scoped_notification!(user:, conversation:)
    create(:notification,
           user: user, account: account, primary_actor: conversation,
           notification_type: :conversation_assignment)
  end

  def delivery_job_hashes_for(notification)
    target_ids = [notification.id]
    enqueued_jobs.select do |job|
      next false unless [Notification::PushNotificationJob, Notification::EmailNotificationJob].include?(job[:job])

      args = ActiveJob::Arguments.deserialize(job[:args])
      args.first.is_a?(Notification) && target_ids.include?(args.first.id)
    end
  end

  def payload_for(job_hash)
    JSON.parse(job_hash.except(:job, :args, :queue, :priority, :at).to_json)
  end

  def mailer_job_hashes
    enqueued_jobs.select { |job| job[:job] == ActionMailer::MailDeliveryJob }
  end

  it 'positivo marcado autorizado: push 1x, 1 email, hash com connecta_scope epoch 1, sem MailDeliveryJob desprotegido' do
    notification = nil
    push_hash = nil
    email_hash = nil
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      expect(jobs.map { |job| job[:job] }).to contain_exactly(Notification::PushNotificationJob,
                                                              Notification::EmailNotificationJob)
      push_hash = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      expect(push_hash['connecta_scope']).to include('v' => 1, 'kind' => 'notification',
                                                     'account_id' => account.id,
                                                     'conversation_id' => conv_a.id,
                                                     'notification_id' => notification.id,
                                                     'user_id' => agent_a.id, 'epoch' => 1)
      expect(email_hash['connecta_scope']).to include('v' => 1, 'kind' => 'notification',
                                                      'notification_id' => notification.id,
                                                      'user_id' => agent_a.id, 'epoch' => 1)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(push_hash)
      ActiveJob::Base.execute(email_hash)
      expect(WebPush).to have_received(:payload_send).once
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(mailer_job_hashes).to be_empty
    end
  end

  it 'revoga grant de A: jobs serializados antes negam push/email na execucao' do
    push_hash = nil
    email_hash = nil
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      push_hash = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(push_hash)
      ActiveJob::Base.execute(email_hash)
      expect(WebPush).not_to have_received(:payload_send)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(mailer_job_hashes).to be_empty
    end
  end

  it 'conversa transferida para B com saida registrada: pendentes de A negados' do
    push_hash = nil
    email_hash = nil
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      push_hash = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(org_unit: org_b,
                                                                                      state: 'transferred_out')
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(push_hash)
      ActiveJob::Base.execute(email_hash)
      expect(WebPush).not_to have_received(:payload_send)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'epoch 1->2 com grant ainda ativo: Gate current sozinho nao basta, pendentes negados' do
    push_hash = nil
    email_hash = nil
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      push_hash = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      expect(Connecta::Scope::UserGrant.where(user_id: agent_a.id).count).to be > 0
      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(epoch: 2)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(push_hash)
      ActiveJob::Base.execute(email_hash)
      expect(WebPush).not_to have_received(:payload_send)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(Connecta::Scope::UserGrant.where(user_id: agent_a.id).count).to be > 0
    end
  end

  it 'legado sem chave em conversa marcada: negado; sem chave em controle: nativo' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      marked = create_scoped_notification!(user: agent_a, conversation: conv_a)
      marked_jobs = delivery_job_hashes_for(marked)
      marked_push = payload_for(marked_jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      marked_push.delete('connecta_scope')
      marked_email = payload_for(marked_jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      marked_email.delete('connecta_scope')
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(marked_push)
      ActiveJob::Base.execute(marked_email)
      expect(WebPush).not_to have_received(:payload_send)
      expect(ActionMailer::Base.deliveries).to be_empty

      allow(WebPush).to receive(:payload_send).and_return(true)
      control = create_scoped_notification!(user: agent_a, conversation: conv_control)
      control_jobs = delivery_job_hashes_for(control)
      control_push = payload_for(control_jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      control_push.delete('connecta_scope')
      ActiveJob::Base.execute(control_push)
      expect(WebPush).to have_received(:payload_send).once
    end
  end

  it 'contexto com user_id de B nao entrega pendente de A' do
    push_hash = nil
    email_hash = nil
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      push_hash = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      push_hash['connecta_scope'] = push_hash['connecta_scope'].merge('user_id' => agent_b.id)
      email_hash['connecta_scope'] = email_hash['connecta_scope'].merge('user_id' => agent_b.id)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(push_hash)
      ActiveJob::Base.execute(email_hash)
      expect(WebPush).not_to have_received(:payload_send)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'controle conv_control sem contexto: envia push e enfileira MailDeliveryJob nativo' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_control)
      jobs = delivery_job_hashes_for(notification)
      push_hash = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      push_hash.delete('connecta_scope')
      email_hash.delete('connecta_scope')
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(push_hash)
      ActiveJob::Base.execute(email_hash)
      expect(WebPush).to have_received(:payload_send).once
      expect(mailer_job_hashes.map { |job| job[:job] }).to include(ActionMailer::MailDeliveryJob)
    end
  end

  it 'retry nao recaptura versao nova: serialize mantem epoch 1, re-enqueue gera epoch 1 e nega apos epoch 2' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      payload = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      job = ActiveJob::Base.deserialize(payload)
      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(epoch: 2)
      expect(job.serialize['connecta_scope']['epoch']).to eq(1)
      clear_enqueued_jobs
      job.enqueue
      retried_hash = payload_for(enqueued_jobs.find { |entry| entry[:job] == Notification::PushNotificationJob })
      expect(retried_hash['connecta_scope']['epoch']).to eq(1)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(retried_hash)
      expect(WebPush).not_to have_received(:payload_send)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'marcado autorizado nao enfileira MailDeliveryJob desprotegido; deliver_now autorizado entrega 1' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(email_hash)
      expect(mailer_job_hashes).to be_empty
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end
  end

  it 'admin nominal jamais recebe pendente de conversa marcada, mesmo com linha existente' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test', VAPID_PUBLIC_KEY: 'test' do
      notification = create_scoped_notification!(user: admin_nominal, conversation: conv_a)
      jobs = delivery_job_hashes_for(notification)
      push_hash = payload_for(jobs.find { |job| job[:job] == Notification::PushNotificationJob })
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(push_hash)
      ActiveJob::Base.execute(email_hash)
      expect(WebPush).not_to have_received(:payload_send)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(Notification.where(id: notification.id).count).to eq(1)
    end
  end
end
