require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# Guardas fora do endpoint: a mesma regra de elegibilidade do alvo vale para
# macros/automação (ActionService pula sem levantar) e para a criação
# (ConversationBuilder ignora assignee inelegível). Sem mocks: projeção real.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · guardas de atribuição por setor', type: :request do # rubocop:disable RSpec/DescribeClass
  include_context 'with connecta g0 scope fixture'

  describe 'AssignmentPolicy.target_eligible?' do
    it 'espelha a regra do allowed?: atender cobre a unidade, o resto não' do
      policy = ->(user) { Connecta::Scope::AssignmentPolicy.target_eligible?(account: account, org_unit: org_a, target_id: user&.id) }

      expect(policy.call(agent_a)).to be(true)
      expect(policy.call(agent_b)).to be(false)
      expect(policy.call(member_without_grant)).to be(false)
      expect(policy.call(admin_nominal)).to be(false)
      expect(policy.call(nil)).to be(false)
    end

    it 'unidade desabilitada não elege ninguém' do
      org_a.update!(enabled: false)

      expect(Connecta::Scope::AssignmentPolicy.target_eligible?(account: account, org_unit: org_a, target_id: agent_a.id)).to be(false)
    end

    it 'bulk por unidade usa a mesma regra' do
      by_unit = Connecta::Scope::AssignmentPolicy.eligible_target_ids_by_unit(account: account, org_units: [org_a, org_b])

      expect(by_unit[org_a.id]).to contain_exactly(agent_a.id)
      expect(by_unit[org_b.id]).to contain_exactly(agent_b.id)
    end
  end

  describe 'ActionService (macro/automação)' do
    it 'pula atribuição a usuário sem atender no setor, sem levantar (AC8)' do
      expect do
        ActionService.new(conv_a).assign_agent([agent_b.id])
      end.not_to raise_error
      expect(conv_a.reload.assignee_id).to be_nil
    end

    it 'atribui usuário com atender no setor (AC8)' do
      ActionService.new(conv_a).assign_agent([agent_a.id])

      expect(conv_a.reload.assignee_id).to eq(agent_a.id)
    end
  end

  describe 'ConversationBuilder' do
    let(:contact_inbox) { create(:contact_inbox, contact: contact_a, inbox: whatsapp_inbox) }

    before do
      stub_const('ENV', ENV.to_h.merge('CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))
    end

    def build_with_assignee(user)
      ConversationBuilder.new(
        params: ActionController::Parameters.new(assignee_id: user&.id),
        contact_inbox: contact_inbox
      ).perform
    end

    it 'ignora assignee sem atender no setor de recepção (AC8)' do
      conversation = build_with_assignee(agent_b)

      expect(conversation.assignee_id).to be_nil
    end

    it 'mantém assignee com atender no setor de recepção' do
      conversation = build_with_assignee(agent_a)

      expect(conversation.assignee_id).to eq(agent_a.id)
    end
  end
end
