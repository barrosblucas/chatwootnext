require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# Defeito 3a (regressão): scope_readable? é privado no Gate, mas o delivery_check
# (contato excluído) chamava com receptor explícito — NoMethodError e o token era
# descartado. O Gate agora expõe readable_scope? (mesma regra) e o delivery_check
# usa o wrapper público.
Connecta::G0ScopeSchema.ensure!

RSpec.describe 'Connecta escopo · Gate público para contato excluído (defeito 3a)' do # rubocop:disable RSpec/DescribeClass -- descreve regra de escopo, não uma classe
  include_context 'with connecta g0 scope fixture'

  let(:scope_a) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }

  it 'readable_scope? aplica a mesma regra de leitura do Gate' do
    expect(Connecta::Scope::Gate.new(agent_a).readable_scope?(scope_a)).to be(true)
    expect(Connecta::Scope::Gate.new(agent_b).readable_scope?(scope_a)).to be(false)
  end

  it 'delivery de contato excluído inclui o agente com leitura no escopo' do
    context = {
      'v' => 1, 'kind' => 'contact_deleted', 'account_id' => account.id,
      'contact_id' => contact_a.id, 'scope_ids' => [scope_a.id],
      'users' => { agent_a.id.to_s => 1, agent_b.id.to_s => 1 }
    }

    tokens = Connecta::Scope::DeliveryCheck.allowed_tokens(context, [agent_a.pubsub_token, agent_b.pubsub_token],
                                                           'contact.deleted', {})

    expect(tokens).to include(agent_a.pubsub_token)
    expect(tokens).not_to include(agent_b.pubsub_token)
  end

  it 'admin nominal continua fora da entrega de contato excluído' do
    context = {
      'v' => 1, 'kind' => 'contact_deleted', 'account_id' => account.id,
      'contact_id' => contact_a.id, 'scope_ids' => [scope_a.id],
      'users' => { admin_nominal.id.to_s => 1 }
    }

    tokens = Connecta::Scope::DeliveryCheck.allowed_tokens(context, [admin_nominal.pubsub_token],
                                                           'contact.deleted', {})

    expect(tokens).to be_empty
  end
end
