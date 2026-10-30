require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'
require_relative 'support/g0_transfer_schema'

# T0.7c-2 (spike G0): integração entre LocalTransaction (API final da T0.7c) e OutboundDispatch (contrato da T0.7b).
# Usa o fixture de escopo (transacional: o rollback limpa tudo, sem after manual) e transporte stubado
# (Whatsapp::SendOnWhatsappService dobrado; SendReplyJob real). Sem dormir, sem rede, sem threads: o "despacho em
# voo" é simulado gravando a linha como dispatching antes do begin!. As expectativas afirmam comportamento
# observável (retornos, estados, chamadas ao conector), não o código interno.
Connecta::G0ScopeSchema.ensure!
Connecta::G0TransferSchema.ensure!
Connecta::Transfer::Installer.install!

RSpec.describe 'Connecta G0 · integração transferência ↔ despacho em voo (T0.7c-2)' do # rubocop:disable RSpec/DescribeClass
  include_context 'with connecta g0 scope fixture'

  let(:dispatches) { Connecta::Transfer::OutboundDispatchRecord }
  let(:transfers) { Connecta::Transfer::TransferRecord }
  let(:origin_scope) { Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id) }
  let(:transfer) { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b) }
  let(:connector) { instance_double(Whatsapp::SendOnWhatsappService, perform: nil) }

  before do
    allow(Whatsapp::SendOnWhatsappService).to receive(:new).and_return(connector)
  end

  it 'begin → commit → activate: origem transferred_out e destino active na versão confirmada' do
    expect(transfer.begin!).to eq(:proceed)
    destination = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: segunda via. Feito: dados. Pendencia: nenhuma.')

    expect(destination).to be_a(Conversation)
    expect(origin_scope.reload.state).to eq('transferred_out')

    transfer.activate!(case_version: 2)

    expect(Connecta::Scope::ConversationScope.find_by!(conversation_id: destination.id))
      .to have_attributes(state: 'active', case_version: 2)
    expect(transfer.record.reload.state).to eq('committed')
  end

  it 'queued estacionado no begin: linha vira parked e o commit prossegue sem chamar o conector' do
    outgoing = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'resposta')

    expect(transfer.begin!).to eq(:proceed)
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('parked')

    destination = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    expect(destination).to be_a(Conversation)
    expect(connector).not_to have_received(:perform)
  end

  it 'dispatching em voo retém em awaiting_dispatch; accepted libera resume e commit' do
    outgoing = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'resposta')
    dispatches.find_by!(message_id: outgoing.id).update!(state: 'dispatching')

    expect(transfer.begin!).to eq(:wait)
    expect(transfer.record.reload.state).to eq('awaiting_dispatch')

    Connecta::Transfer::OutboundDispatch.resolve!(outgoing, 'accepted')

    expect(transfer.resume!).to eq(:proceed)
    expect(transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')).to be_a(Conversation)
  end

  it 'dispatching em voo com failed libera resume e commit sem reenvio' do
    outgoing = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'resposta')
    dispatches.find_by!(message_id: outgoing.id).update!(state: 'dispatching')

    expect(transfer.begin!).to eq(:wait)
    expect(transfer.record.reload.state).to eq('awaiting_dispatch')

    Connecta::Transfer::OutboundDispatch.resolve!(outgoing, 'failed')

    expect(transfer.resume!).to eq(:proceed)
    expect(transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')).to be_a(Conversation)

    SendReplyJob.perform_now(outgoing.id)

    expect(connector).not_to have_received(:perform)
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('failed')
  end

  it 'uncertain no begin: ConflictError, origem volta a active e pedido vai a aborted' do
    outgoing = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'resposta')
    dispatches.find_by!(message_id: outgoing.id).update!(state: 'uncertain')

    expect { transfer.begin! }
      .to(raise_error { |error| expect(error.class.name).to eq('Connecta::Transfer::OutboundDispatch::ConflictError') })
    expect(origin_scope.reload.state).to eq('active')
    expect(transfer.record.reload.state).to eq('aborted')
  end

  it 'uncertain depois do begin: commit revalida, levanta ConflictError e desfaz o preparo' do
    expect(transfer.begin!).to eq(:proceed)
    outgoing = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'tardia')
    dispatches.find_by!(message_id: outgoing.id).update!(state: 'uncertain')

    expect { transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.') }
      .to(raise_error { |error| expect(error.class.name).to eq('Connecta::Transfer::OutboundDispatch::ConflictError') })
    expect(origin_scope.reload.state).to eq('active')
    expect(transfer.record.reload.state).to eq('aborted')
  end

  it 'worker atrasado depois do commit: job não chama o conector e a linha continua parked' do
    outgoing = create(:message, account: account, conversation: conv_a, message_type: :outgoing, content: 'resposta')
    transfer.begin!
    transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    SendReplyJob.perform_now(outgoing.id)

    expect(connector).not_to have_received(:perform)
    expect(dispatches.find_by!(message_id: outgoing.id).state).to eq('parked')
  end

  it 'begin e commit idempotentes: repetição reutiliza o pedido e devolve o mesmo destino' do
    expect(transfer.begin!).to eq(:proceed)
    expect(transfer.begin!).to eq(:proceed)

    first = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')
    second = transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    expect(second.id).to eq(first.id)
    expect(transfers.where(source_conversation_id: conv_a.id).count).to eq(1)
  end

  it 'activate só com a versão confirmada; versão errada não muda nada' do
    transfer.begin!
    transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    expect { transfer.activate!(case_version: 1) }
      .to(raise_error { |error| expect(error.class.name).to eq('Connecta::Transfer::LocalTransaction::VersionMismatch') })
    expect(transfer.record.reload.state).to eq('committed_local')

    transfer.activate!(case_version: 2)

    expect(transfer.record.reload.state).to eq('committed')
  end

  it 'depois do commit nada reabre a origem: abort e nova transferência falham' do
    transfer.begin!
    transfer.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')

    expect { transfer.abort! }.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotFound') })
    expect { Connecta::Transfer::LocalTransaction.new(scope: origin_scope, destination_org_unit: org_b).call }
      .to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotFound') })
    expect(origin_scope.reload.state).to eq('transferred_out')
  end

  it 'controle em inbox não marcada: sem barreira, sem linha de despacho, transferência prossegue' do
    control_scope = Connecta::Scope::ConversationScope.create!(
      conversation_id: conv_control.id, inbox_id: control_inbox.id, contact_id: contact_control.id,
      org_unit: org_a, state: 'active', case_protocol: 'CASO-CONTROLE', case_version: 1
    )
    control_message = create(:message, account: account, conversation: conv_control, message_type: :outgoing, content: 'controle')
    control = Connecta::Transfer::LocalTransaction.new(scope: control_scope, destination_org_unit: org_b)

    expect(control.begin!).to eq(:proceed)
    expect(control.commit_local!(target_case_version: 2, summary: 'Assunto: a. Feito: b. Pendencia: c.')).to be_a(Conversation)
    expect(dispatches.where(message_id: control_message.id).count).to eq(0)
  end
end
