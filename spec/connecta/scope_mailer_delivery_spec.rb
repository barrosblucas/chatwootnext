require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF4 email ponto final (spike G0, rev. 2, bloco M2): MailDeliveryJob nativo pendente
# falha fechado em conversa marcada; guard final before_deliver (M1) rele escopo/epoch
# apos o guard do Parent; novo fluxo EmailNotificationJob autorizado entrega 1 via
# Mailer real sem enfileirar MailDeliveryJob desprotegido. Casos ESCRITOS e NAO
# EXECUTADOS; M1 implementa o guard em runtime (plano rev. 2, l. 169-190). Somente API
# publica nativa: deliver_later, enqueued_jobs, JSON round-trip, Base.execute, ORM
# fixtures. Nenhum Gate/before_deliver/perform stubado; nenhum helper novo da infra
# chamado; sem SMTP externo; sem Vite. Execucao real pendente (Bloco D); RF4 NAO validado.
# Nome segue o briefing (scope_mailer_delivery_spec.rb); plano l. 180 usa outro nome
# (desvio registrado em .context/evidence/g0/44-rf4-mailer-spec.md).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Casos M2 juntam legado+endpoint+race por caso (AC1/AC2); expectativas agrupadas
# por caso para manter a suite focada (<= 15 min de execucao).
RSpec.describe 'Connecta G0 · email pendente no ponto final (RF4/M2)', type: :request do
  include_context 'with connecta g0 scope fixture'

  # config/initializers/mailer.rb troca para :sendmail quando SMTP_ADDRESS está vazio (o runner usa env -i).
  # Este spec prova o fluxo sem entrega real: fixa :test e restaura ao fim.
  let!(:previous_delivery_method) { ActionMailer::Base.delivery_method }

  before do
    ActionMailer::Base.delivery_method = :test
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
    [agent_a, agent_b, manager_a, member_without_grant, admin_nominal].each do |user|
      user.notification_settings.find_by(account_id: account.id).update!(
        selected_email_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"email_#{type}" },
        selected_push_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"push_#{type}" }
      )
      user.update!(confirmed_at: Time.current) if user.confirmed_at.nil?
    end
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

  def mailer_job_hashes
    enqueued_jobs.select { |job| job[:job] == ActionMailer::MailDeliveryJob }
  end

  def payload_for(job_hash)
    JSON.parse(job_hash.except(:job, :args, :queue, :priority, :at).to_json)
  end

  def legacy_mailer_payload_for(conversation, agent)
    clear_enqueued_jobs
    AgentNotifications::ConversationNotificationsMailer.with(account: account).conversation_assignment(conversation, agent, nil).deliver_later
    hashes = mailer_job_hashes
    raise 'esperava 1 MailDeliveryJob pendente' unless hashes.size == 1

    payload_for(hashes.first)
  end

  def email_job_hashes_for(notification)
    target_ids = [notification.id]
    enqueued_jobs.select do |job|
      next false unless job[:job] == Notification::EmailNotificationJob

      args = ActiveJob::Arguments.deserialize(job[:args])
      args.first.is_a?(Notification) && target_ids.include?(args.first.id)
    end
  end

  it 'legado marcado pendente: revoga grant de A antes de executar nega 0 (fail-closed)' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test' do
      payload = legacy_mailer_payload_for(conv_a, agent_a)
      Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(payload)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(mailer_job_hashes).to be_empty
    end
  end

  it 'legado marcado pendente: transferencia para B com saida registrada nega 0' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test' do
      payload = legacy_mailer_payload_for(conv_a, agent_a)
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(org_unit: org_b, state: 'transferred_out')
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(payload)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'legado marcado pendente: epoch 1->2 com grant ainda ativo nega 0 (Gate current sozinho nao basta)' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test' do
      payload = legacy_mailer_payload_for(conv_a, agent_a)
      expect(Connecta::Scope::UserGrant.where(user_id: agent_a.id).count).to be > 0
      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(epoch: 2)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(payload)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(Connecta::Scope::UserGrant.where(user_id: agent_a.id).count).to be > 0
    end
  end

  it 'legado marcado pendente sem mudar estado nega 0 (marcado sem contexto falha fechado)' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test' do
      payload = legacy_mailer_payload_for(conv_a, agent_a)
      expect(Connecta::Scope::UserGrant.where(user_id: agent_a.id).count).to be > 0
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(payload)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'fluxo novo marcado: EmailNotificationJob autorizado entrega 1 sem MailDeliveryJob; user e epoch trocados negam' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = email_job_hashes_for(notification)
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      expect(email_hash['connecta_scope']).to include('v' => 1, 'kind' => 'notification',
                                                      'notification_id' => notification.id,
                                                      'user_id' => agent_a.id, 'epoch' => 1)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(email_hash)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(mailer_job_hashes).to be_empty

      mismatch_notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      mismatch_jobs = email_job_hashes_for(mismatch_notification)
      mismatch_hash = payload_for(mismatch_jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      mismatch_hash['connecta_scope'] = mismatch_hash['connecta_scope'].merge('user_id' => agent_b.id)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(mismatch_hash)
      expect(ActionMailer::Base.deliveries).to be_empty

      epoch_notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      epoch_jobs = email_job_hashes_for(epoch_notification)
      epoch_hash = payload_for(epoch_jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      Connecta::Scope::UserAuthEpoch.find_by!(user_id: agent_a.id).update!(epoch: 2)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(epoch_hash)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'controle nao marcado: MailDeliveryJob nativo sem contexto entrega 1 sem rede externa' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test' do
      payload = legacy_mailer_payload_for(conv_control, member_without_grant)
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      ActiveJob::Base.execute(payload)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  it 'barreira final: Parent passa com ctx valido e revogacao durante o Mailer aborta SMTP 0' do
    with_modified_env SMTP_ADDRESS: 'smtp.example.test' do
      notification = create_scoped_notification!(user: agent_a, conversation: conv_a)
      jobs = email_job_hashes_for(notification)
      email_hash = payload_for(jobs.find { |job| job[:job] == Notification::EmailNotificationJob })
      expect(email_hash['connecta_scope']).to include('epoch' => 1, 'user_id' => agent_a.id)
      target_user_id = agent_a.id
      AgentNotifications::ConversationNotificationsMailer.define_method(:connecta_scope_test_race_hook!) do
        Connecta::Scope::UserAuthEpoch.find_by!(user_id: target_user_id).update!(epoch: 2)
      end
      AgentNotifications::ConversationNotificationsMailer.before_deliver(:connecta_scope_test_race_hook!,
                                                                         prepend: true)
      begin
        clear_enqueued_jobs
        ActionMailer::Base.deliveries.clear
        ActiveJob::Base.execute(email_hash)
        expect(ActionMailer::Base.deliveries).to be_empty
        expect(Connecta::Scope::UserGrant.where(user_id: target_user_id).count).to be > 0
      ensure
        AgentNotifications::ConversationNotificationsMailer.skip_callback(:deliver, :before,
                                                                          :connecta_scope_test_race_hook!,
                                                                          raise: false)
      end
    end
  end
end
