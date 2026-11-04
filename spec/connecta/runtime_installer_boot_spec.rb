require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'

# Tolerância do boot C7: com inbox marcada e sem unidade de recepção configurada
# (conta fresca — o enforce vem depois, pelo upsert oficial), o boot NÃO pode
# travar: registra connecta_reception_unit_missing com a contagem e continua.
# O fail-closed continua em ReceptionScopeCreator.call (conversa nova sem unidade).
Connecta::G0ScopeSchema.ensure!

RSpec.describe Connecta::Runtime::Installer do
  describe '.install! with a marked inbox but no reception unit' do
    around do |example|
      previous = ENV.delete('CONNECTA_RECEPTION_ORG_UNIT_ID')
      example.run
      ENV['CONNECTA_RECEPTION_ORG_UNIT_ID'] = previous if previous
    end

    before do
      described_class.remove_instance_variable(:@installed) if described_class.instance_variable_defined?(:@installed)
      allow(Connecta::Runtime::Feature).to receive(:enabled?).and_return(true)
      allow(Connecta::Runtime::G0Adapter).to receive(:install!).and_return(true)
      allow(Connecta::Scope::Installer).to receive_messages(
        install_policies_and_finders!: true, install_conversations!: true,
        install_notifications_and_mentions!: true, install_contacts!: true,
        install_inboxes_and_captain!: true, install_attachments!: true,
        install_realtime!: true, install_denied_rendering!: true
      )
    end

    after do
      described_class.remove_instance_variable(:@installed) if described_class.instance_variable_defined?(:@installed)
    end

    it 'does not raise, logs the missing unit with the count, and finishes boot' do
      account = create(:account)
      inbox = create(:inbox, account: account)
      Connecta::Scope::ScopedInbox.create!(inbox_id: inbox.id, enforcement: 'enforce', maintenance: false)
      allow(Rails.logger).to receive(:error)

      expect { described_class.install! }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/connecta_reception_unit_missing marked_inbox_count=1/)
    end
  end
end
