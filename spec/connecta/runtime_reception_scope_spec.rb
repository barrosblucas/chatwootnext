require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'

# Defeito 3c: sem unidade de recepção configurada o criador não pode só logar e
# omitir o escopo (fail-closed silencioso). Agora a falha é explícita e
# reconciliável: MissingReceptionUnit no call e no boot quando há inbox marcada.
Connecta::G0ScopeSchema.ensure!
# Scope aponta às tabelas de produto (mesmo mapa de G0Adapter::TABLES; ver support/g0_product_tables.rb).
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · escopo de recepção (defeito 3c)' do # rubocop:disable RSpec/DescribeClass -- descreve regra de escopo, não uma classe
  include_context 'with connecta g0 scope fixture'

  let(:fresh_contact) { create(:contact, account: account) }
  let(:fresh_conversation) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: fresh_contact) }

  before do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_ACCOUNT_ID' => account.id.to_s))
    # A fixture cria inbox members, e o callback do Chatwoot empurra o agente para a fila de round-robin
    # no Redis (InboxMember -> InboxRoundRobinService#add_agent_to_queue). Este spec prova escopo, não fila:
    # a fila é stubada para não depender de Redis real.
    allow(Redis::Alfred).to receive(:lpush)
    allow(Redis::Alfred).to receive(:lrem)
    allow(Redis::Alfred).to receive(:delete)
  end

  it 'cria escopo reception quando a unidade esta configurada' do
    stub_const('ENV', ENV.to_h.merge('CONNECTA_RECEPTION_ORG_UNIT_ID' => org_a.id.to_s))

    scope = Connecta::Runtime::ReceptionScopeCreator.call(fresh_conversation)

    expect(scope).to have_attributes(state: 'reception', case_version: 0, inbox_id: whatsapp_inbox.id,
                                     contact_id: fresh_contact.id, org_unit_id: org_a.id)
  end

  it 'sem unidade configurada a falha e explicita (nao omite o escopo em silencio)' do
    stub_const('ENV', ENV.to_h.except('CONNECTA_RECEPTION_ORG_UNIT_ID'))

    expect { Connecta::Runtime::ReceptionScopeCreator.call(fresh_conversation) }
      .to raise_error(Connecta::Runtime::ReceptionScopeCreator::MissingReceptionUnit)
    expect(Connecta::Scope::ConversationScope.find_by(conversation_id: fresh_conversation.id)).to be_nil
  end

  it 'boot valida a configuracao quando ha inbox marcada' do
    stub_const('ENV', ENV.to_h.except('CONNECTA_RECEPTION_ORG_UNIT_ID'))

    expect { Connecta::Runtime::ReceptionScopeCreator.verify_marked_inboxes! }
      .to raise_error(Connecta::Runtime::ReceptionScopeCreator::MissingReceptionUnit)
  end

  it 'inbox nao marcada continua sem escopo (sem erro)' do
    stub_const('ENV', ENV.to_h.except('CONNECTA_RECEPTION_ORG_UNIT_ID'))
    marked_inbox.destroy!

    expect(Connecta::Runtime::ReceptionScopeCreator.call(fresh_conversation)).to be_nil
  end
end
