require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_transfer_schema'
require_relative 'support/g0_scope_fixture'

# Correção 01 (contador + visibilidade do destino): ao ativar, o destino
# nasce pending_activation (invisível: fora de READ_STATES, o gate derruba o
# conversation.created do create!), então só um reanúncio pós-commit faz os
# agentes do destino verem sem reload. O scope.revoked da origem precisa
# alcançar leitores por grant ancestral e admins nativos (gate.rb).
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Scope::Installer.install!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta · anúncio da ativação e destinatários do scope.revoked', type: :request do
  include ActiveJob::TestHelper
  include_context 'with connecta g0 scope fixture'

  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let!(:descendant_agent) { create(:user, account: account, role: :agent) }
  let(:origin_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }
  let(:local) { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b) }
  let(:summary) { 'Assunto: segunda via. Feito: dados conferidos. Pendencia: retorno do setor B.' }

  before do
    [native_admin, descendant_agent].each do |user|
      create(:inbox_member, inbox: whatsapp_inbox, user: user)
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    Connecta::Scope::UserGrant.create!(user_id: descendant_agent.id, org_unit: org_a1, permission: 'atender')
    local.begin!
    local.commit_local!(target_case_version: 2, summary: summary)
    clear_enqueued_jobs
  end

  after do
    clear_enqueued_jobs
  end

  def member_created_jobs
    enqueued_jobs.select { |entry| entry[:job] == ActionCableBroadcastJob }.filter_map do |entry|
      tokens, event_name, payload = ActiveJob::Arguments.deserialize(entry[:args])
      next unless event_name == Events::Types::CONVERSATION_CREATED

      [tokens, payload]
    end
  end

  it 'activate! anuncia conversation.created só aos leitores do destino' do
    allow(ActionCable.server).to receive(:broadcast)

    expect { local.activate!(case_version: 2) }.to have_enqueued_job(ActionCableBroadcastJob)

    member_job = member_created_jobs.find { |tokens, _payload| tokens.include?(agent_b.pubsub_token) }
    expect(member_job).not_to be_nil
    _tokens, payload = member_job
    expect(payload['account_id']).to eq(account.id)

    announced_tokens = member_created_jobs.flat_map(&:first)
    expect(announced_tokens).not_to include(agent_a.pubsub_token, member_without_grant.pubsub_token)
  end

  it 'activate! idempotente não reanuncia o destino' do
    allow(ActionCable.server).to receive(:broadcast)
    local.activate!(case_version: 2)
    clear_enqueued_jobs

    expect { local.activate!(case_version: 2) }.not_to have_enqueued_job(ActionCableBroadcastJob)
  end

  it 'scope.revoked alcança grant ancestral e admin nativo, sem vazar a descendente/sem grant' do
    collected = []
    allow(ActionCable.server).to receive(:broadcast) do |stream, message|
      collected << [stream, message]
    end

    Connecta::Runtime::CacheRevocation.scope!(origin_scope)

    revoked = collected.select { |_stream, message| message[:event] == 'scope.revoked' }
    expect(revoked).not_to be_empty
    streams = revoked.map(&:first)
    expect(streams).to include(agent_a.pubsub_token, manager_a.pubsub_token, admin_nominal.pubsub_token,
                               native_admin.pubsub_token)
    expect(streams).not_to include(agent_b.pubsub_token, member_without_grant.pubsub_token,
                                   descendant_agent.pubsub_token)
    _stream, message = revoked.first
    expect(message[:data]).to include(account_id: account.id, conversation_id: conv_a.display_id)
  end
end
