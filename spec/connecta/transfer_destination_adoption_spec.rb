require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_product_tables'
require_relative 'support/g0_transfer_schema'

# Adoção do escopo de recepção do callback em open_destination:
# Conversation.create! dispara ReceptionScopeCreator via after_create (síncrono, mesma
# transação), que insere reception/version0/protocolo-nil antes do segundo create.
# O segundo create violaria os únicos de conversation e de (inbox, contato) aberto.
# A correção adota SOMENTE o escopo pristine do callback (mesma conversa/conta/inbox/
# contato, reception/version0/sem protocolo/sem transfer/session/ativação/fechamento)
# convertendo para pending_activation + protocolo da origem + version0 (alvo source+1
# fica no transfer/activated, NÃO neste escopo). Qualquer escopo ativo/estranho/divergente
# falha com RecordNotFound (409 com compensação precommit); ausente mantém create normal.
# Idempotente: commit repetido devolve o mesmo destino sem duplicar; falha dá rollback.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::G0ProductTables.install!

RSpec.describe 'Connecta runtime · adoção do escopo de recepção do callback' do # rubocop:disable RSpec/DescribeClass
  include_context 'with connecta g0 scope fixture'

  let(:origin_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }
  let(:transfer) { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b) }

  before do
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(instance_double(Whatsapp::SendOnWhatsappService, perform: nil))
  end

  def with_callback_scope(state_attrs = {})
    allow(Conversation).to receive(:create!).and_wrap_original do |original, *args|
      conversation = original.call(*args)
      defaults = {
        conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
        org_unit: org_a, state: 'reception', case_protocol: nil, case_version: 0
      }
      Connecta::Scope::ConversationScope.create!(defaults.merge(state_attrs))
      conversation
    end
  end

  it 'callback pristine vira um único pending_activation sem erro de unicidade' do
    with_callback_scope
    expect(transfer.begin!).to eq(:proceed)

    destination = nil
    expect {
      destination = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')
    }.not_to raise_error

    expect(destination).to be_a(Conversation)
    scopes = Connecta::Scope::ConversationScope.where(conversation_id: destination.id).to_a
    expect(scopes.size).to eq(1)
    expect(scopes.first).to have_attributes(
      state: 'pending_activation', case_version: 0, case_protocol: 'CASO-A',
      inbox_id: origin_scope.inbox_id, contact_id: origin_scope.contact_id
    )
    expect(scopes.first.org_unit_id).to eq(org_b.id)
    expect(transfer.record.reload).to have_attributes(state: 'committed_local', target_case_version: 2)
  end

  it 'ausência do callback mantém o create normal' do
    expect(transfer.begin!).to eq(:proceed)
    destination = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    expect(destination).to be_a(Conversation)
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: destination.id))
      .to have_attributes(state: 'pending_activation', case_version: 0, case_protocol: 'CASO-A')
  end

  it 'mesmo transfer repetido devolve o mesmo destino sem duplicar conversa/escopo' do
    with_callback_scope
    expect(transfer.begin!).to eq(:proceed)
    first = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    expect {
      second = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')
      expect(second.id).to eq(first.id)
    }.not_to change(Conversation, :count)

    expect(Connecta::Scope::ConversationScope.where(conversation_id: first.id).count).to eq(1)
    expect(Connecta::Transfer::TransferRecord.where(source_conversation_id: conv_a.id).count).to eq(1)
  end

  it 'escopo ativo do callback é rejeitado sem sobrescrever' do
    with_callback_scope(state: 'active', case_protocol: 'CASO-X', case_version: 1)
    expect(transfer.begin!).to eq(:proceed)

    expect {
      transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')
    }.to raise_error(ActiveRecord::RecordNotFound)

    expect(origin_scope.reload.state).to eq('transferring')
    expect(transfer.record.reload.state).to eq('requested')
  end

  it 'identidade/versão/associação divergente é rejeitada' do
    expect(transfer.begin!).to eq(:proceed)
    [
      { case_version: 1 },
      { case_protocol: 'CASO-X' },
      { transfer_id: SecureRandom.uuid },
      { platform_session_ref: 'sess' },
      { activated_at: Time.current },
      { closed_at: Time.current },
      { inbox_id: 999_999 },
      { contact_id: 999_999 }
    ].each do |override|
      allow(Conversation).to receive(:create!).and_wrap_original do |original, *args|
        conversation = original.call(*args)
        scope = Connecta::Scope::ConversationScope.create!(
          conversation_id: conversation.id, inbox_id: conversation.inbox_id, contact_id: conversation.contact_id,
          org_unit: org_b, state: 'reception', case_protocol: nil, case_version: 0
        )
        # Aplica a divergência após o callback, ainda dentro da mesma transação do commit.
        scope.update!(override)
        conversation
      end

      expect {
        transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
    expect(origin_scope.reload.state).to eq('transferring')
  end

  it 'falha na adoção dá rollback de origem/destino sem conversa sem escopo' do
    with_callback_scope(state: 'active', case_protocol: 'CASO-X', case_version: 1)
    expect(transfer.begin!).to eq(:proceed)

    conversations_before = Conversation.count
    scopes_before = Connecta::Scope::ConversationScope.count

    expect {
      transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')
    }.to raise_error(ActiveRecord::RecordNotFound)

    expect(Conversation.count).to eq(conversations_before)
    expect(Connecta::Scope::ConversationScope.count).to eq(scopes_before)
    expect(origin_scope.reload.state).to eq('transferring')
  end

  it 'pending mantém version0 e o alvo source+1 fica no transfer/activated' do
    with_callback_scope
    expect(transfer.begin!).to eq(:proceed)
    destination = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: destination.id).case_version).to eq(0)
    expect(transfer.record.reload.target_case_version).to eq(2)

    transfer.activate!(case_version: 2)
    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: destination.id))
      .to have_attributes(state: 'active', case_version: 2)
  end
end
