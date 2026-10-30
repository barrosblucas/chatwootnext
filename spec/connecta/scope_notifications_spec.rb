require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2-c5 (spike G0): notificações e menções de conversas de inbox marcada só chegam a quem o Gate permite ler como agente.
# Listeners e jobs são os reais; nenhuma decisão de autorização é mockada. Os controles em inbox não marcada seguem a regra nativa.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · notificações de conversas marcadas (T0.2-c5)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:listener) { NotificationListener.instance }

  before do
    [agent_a, agent_b, manager_a, member_without_grant, admin_nominal].each do |user|
      user.notification_settings.find_by(account_id: account.id).update!(
        selected_email_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"email_#{type}" },
        selected_push_flags: Notification::NOTIFICATION_TYPES.keys.map { |type| :"push_#{type}" }
      )
    end
  end

  describe 'criação de conversa' do
    let(:created_event) { Events::Base.new(:'conversation.created', Time.zone.now, conversation: conv_a) }

    it 'notifica agente A e acompanhar (leitura pelo Gate); não notifica agente B nem membro sem grant' do
      listener.conversation_created(created_event)

      notified = Notification.where(notification_type: 'conversation_creation', primary_actor: conv_a).pluck(:user_id)
      expect(notified).to include(agent_a.id, manager_a.id)
      expect(notified).not_to include(agent_b.id, member_without_grant.id)
    end

    it 'não notifica o admin nominal sobre conversa da inbox marcada (leitura de admin só pelo detalhe auditado)' do
      listener.conversation_created(created_event)

      notified = Notification.where(notification_type: 'conversation_creation', primary_actor: conv_a).pluck(:user_id)
      expect(notified).not_to include(admin_nominal.id)
    end

    it 'controle: inbox não marcada segue a regra nativa, em que o membro é notificado sem grant' do
      create(:inbox_member, inbox: control_inbox, user: member_without_grant)
      listener.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conv_control))

      notified = Notification.where(notification_type: 'conversation_creation', primary_actor: conv_control).pluck(:user_id)
      expect(notified).to contain_exactly(agent_a.id, member_without_grant.id)
    end
  end

  describe 'nova mensagem' do
    it 'notifica o responsável com grant e não o participante de outro setor' do
      conv_a.update!(assignee: agent_a)
      conv_a.conversation_participants.create!(user: agent_b)
      message = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: contact_a)

      listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: message))

      notified = Notification.where(
        notification_type: %w[assigned_conversation_new_message participating_conversation_new_message], primary_actor: conv_a
      ).pluck(:user_id)
      expect(notified).to contain_exactly(agent_a.id)
    end
  end

  describe 'atribuição' do
    it 'notifica o agente A quando a conversa do setor A é atribuída a ele' do
      conv_a.update!(assignee: agent_a)

      listener.assignee_changed(Events::Base.new(:'assignee.changed', Time.zone.now, conversation: conv_a, notifiable_assignee_change: true))

      expect(Notification.where(notification_type: 'conversation_assignment', primary_actor: conv_a).pluck(:user_id)).to eq([agent_a.id])
    end

    it 'não notifica agente B quando a conversa do setor A é atribuída a ele' do
      conv_a.update!(assignee: agent_b)

      listener.assignee_changed(Events::Base.new(:'assignee.changed', Time.zone.now, conversation: conv_a, notifiable_assignee_change: true))

      expect(Notification.where(notification_type: 'conversation_assignment', primary_actor: conv_a).pluck(:user_id)).to be_empty
    end

    it 'não notifica o admin nominal quando a conversa da inbox marcada é atribuída a ele' do
      conv_a.update!(assignee: admin_nominal)

      listener.assignee_changed(Events::Base.new(:'assignee.changed', Time.zone.now, conversation: conv_a, notifiable_assignee_change: true))

      expect(Notification.where(notification_type: 'conversation_assignment', primary_actor: conv_a)).to be_empty
    end
  end

  describe 'push e email' do
    it 'enfileira push e email só para quem o Gate permite ler' do
      clear_enqueued_jobs
      listener.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conv_a))

      delivery_jobs = enqueued_jobs.select { |job| [Notification::PushNotificationJob, Notification::EmailNotificationJob].include?(job[:job]) }
      recipients = delivery_jobs.map { |job| GlobalID::Locator.locate(job[:args].first['_aj_globalid']).user_id }
      expect(recipients).to include(agent_a.id, manager_a.id)
      expect(recipients).not_to include(agent_b.id, member_without_grant.id, admin_nominal.id)
    end
  end

  describe 'listagem de notificações (GET)' do
    it 'agente B não lista notificação de conversa de A; agente A lista (controle)' do
      listener.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conv_a))

      get "/api/v1/accounts/#{account.id}/notifications", headers: agent_b.create_new_auth_token
      expect(JSON.parse(response.body)['data']['payload'].pluck('primary_actor_id')).not_to include(conv_a.id)

      get "/api/v1/accounts/#{account.id}/notifications", headers: agent_a.create_new_auth_token
      expect(JSON.parse(response.body)['data']['payload'].pluck('primary_actor_id')).to include(conv_a.id)
    end
  end

  describe 'menção em inbox marcada' do
    let!(:mention_message) do
      create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a, message_type: :outgoing, private: true,
                       content: "[#{agent_b.name}](mention://user/#{agent_b.id}/#{agent_b.name})")
    end

    before { listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: mention_message)) }

    it 'menção a agente B sem leitura pelo Gate: a mensagem é salva, B não vira participante e não recebe notificação' do
      expect(mention_message).to be_persisted
      expect(conv_a.conversation_participants.pluck(:user_id)).not_to include(agent_b.id)
      expect(Notification.where(user: agent_b, primary_actor: conv_a)).to be_empty
    end

    it 'menção a agente B sem leitura não cria registro de menção, nem quando o job pendente roda' do
      perform_enqueued_jobs(only: Conversations::UserMentionJob)

      expect(Mention.where(user_id: agent_b.id)).to be_empty
    end

    it 'menção ao admin nominal não o torna participante nem gera notificação' do
      admin_mention = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a, message_type: :outgoing,
                                       private: true, content: "[#{admin_nominal.name}](mention://user/#{admin_nominal.id}/#{admin_nominal.name})")
      listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: admin_mention))

      expect(conv_a.conversation_participants.pluck(:user_id)).not_to include(admin_nominal.id)
      expect(Notification.where(user: admin_nominal, notification_type: 'conversation_mention')).to be_empty
    end
  end

  describe 'menção em inbox não marcada (controle)' do
    before do
      create(:inbox_member, inbox: control_inbox, user: agent_b)
      control_mention = create(:message, account: account, inbox: control_inbox, conversation: conv_control, sender: agent_a,
                                         message_type: :outgoing, private: true,
                                         content: "[#{agent_b.name}](mention://user/#{agent_b.id}/#{agent_b.name})")
      listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: control_mention))
    end

    it 'adiciona B como participante e cria o registro de menção (regra nativa)' do
      perform_enqueued_jobs(only: Conversations::UserMentionJob)

      expect(conv_control.conversation_participants.pluck(:user_id)).to include(agent_b.id)
      expect(Mention.where(user_id: agent_b.id, conversation_id: conv_control.id)).to exist
    end

    it 'gera notificação de menção para B (regra nativa)' do
      expect(Notification.where(user: agent_b, notification_type: 'conversation_mention', primary_actor: conv_control)).to exist
    end
  end

  describe 'listagem participating (GET)' do
    it 'agente B, participante anterior à correção, não lista conversa de inbox marcada sem leitura pelo Gate' do
      conv_a.conversation_participants.create!(user: agent_b)

      get conversations_path, params: { conversation_type: 'participating' }, headers: agent_b.create_new_auth_token

      expect(JSON.parse(response.body)['data']['payload'].pluck('id')).not_to include(conv_a.display_id)
    end

    it 'admin nominal, participante anterior à correção, não lista conversa de inbox marcada' do
      conv_a.conversation_participants.create!(user: admin_nominal)

      get conversations_path, params: { conversation_type: 'participating' }, headers: admin_nominal.create_new_auth_token

      expect(JSON.parse(response.body)['data']['payload'].pluck('id')).not_to include(conv_a.display_id)
    end

    it 'controle: agente B lista conversa de inbox não marcada em que é participante (regra nativa)' do
      create(:inbox_member, inbox: control_inbox, user: agent_b)
      conv_control.conversation_participants.create!(user: agent_b)

      get conversations_path, params: { conversation_type: 'participating' }, headers: agent_b.create_new_auth_token

      expect(JSON.parse(response.body)['data']['payload'].pluck('id')).to contain_exactly(conv_control.display_id)
    end
  end
end
