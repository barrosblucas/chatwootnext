require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'

# Modo runtime (tabelas de produto, igual producao com G0Adapter.install!):
# o commit local da transferencia revoga o escopo da origem e precisa anunciar
# scope.revoked aos leitores certos sem levantar (o announce nunca aborta o
# commit). Regression: LIKE com tabela g0 hardcoded quebrava tudo aqui com
# StatementInvalid, invisivel nos specs em modo G0.
Connecta::G0ScopeSchema.ensure!
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · scope.revoked no commit da transferência' do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper
  include_context 'with connecta g0 scope fixture'

  let(:sent) { [] }
  let(:client) do
    recipient = sent
    stub = Object.new
    stub.define_singleton_method(:post) do |path, payload|
      recipient << { method: :post, path: path, payload: payload }
      { 'case_version' => 1, 'to_session_ref' => 'sess-9' }
    end
    stub
  end
  let(:summary) { { 'subject' => 'Segunda via', 'completed' => 'Dados conferidos', 'next_action' => 'Retorno do setor B' } }

  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let!(:descendant_agent) { create(:user, account: account, role: :agent) }

  before do
    [native_admin, descendant_agent].each do |user|
      create(:inbox_member, inbox: whatsapp_inbox, user: user)
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    Connecta::Scope::UserGrant.create!(user_id: descendant_agent.id, org_unit: org_a1, permission: 'atender')
    Connecta::Scope::UserAuthEpoch.find_by!(user_id: manager_a.id).update!(revoked_locally_at: Time.current)
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s, 'CONNECTA_HUMAN_NUMBER_ENABLED' => 'true',
                                     'CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))
    allow(Connecta::Runtime::PlatformClient).to receive(:new).and_return(client)
    allow(Connecta::Runtime::TransferCommitJob).to receive(:perform_later)
    allow(Connecta::Runtime::TransferAbortJob).to receive(:perform_later)
    Connecta::UserGrant.create!(user_id: agent_a.id, org_unit_id: org_a.id, permission: 'transferir')
  end

  def transfer!
    Connecta::Runtime::TransferTransaction.new(
      account_id: account.id, conversation: conv_a, actor: agent_a,
      destination_org_unit_id: org_b.id, summary: summary
    ).call
  end

  def revoked_streams
    collected = []
    allow(ActionCable.server).to receive(:broadcast) do |stream, message|
      collected << [stream, message]
    end
    result = transfer!
    [result, collected.select { |_stream, message| message[:event] == 'scope.revoked' }.map(&:first)]
  end

  it 'commit integral anuncia scope.revoked aos leitores (epoch revogado fora)' do
    result, streams = revoked_streams

    expect(result[:status]).to eq('pending_activation')
    expect(streams).to include(agent_a.pubsub_token, admin_nominal.pubsub_token, native_admin.pubsub_token)
    expect(streams).not_to include(agent_b.pubsub_token, member_without_grant.pubsub_token,
                                   descendant_agent.pubsub_token, manager_a.pubsub_token)
  end
end
