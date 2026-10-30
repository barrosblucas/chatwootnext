require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

# Regressão: G0Adapter.install! estourava FrozenError ao mutar validator.options (Rails 7.1 congela
# o hash). O adapter não expande mais os estados: o modelo de produto já é a fonte da lista.
# As tabelas de produto vêm das migrações; este spec não cria schema do protótipo G0.
RSpec.describe Connecta::Runtime::G0Adapter do # rubocop:disable RSpec/SpecFilePathFormat -- layout plano de specs do G0; renomear o arquivo quebraria referências em evidências
  describe '.install!' do
    it 'não levanta exceção e é idempotente' do
      expect { described_class.install! }.not_to raise_error
      expect { described_class.install! }.not_to raise_error
    end

    it 'retorna true quando as tabelas connecta_* existem' do
      expect(described_class.install!).to be(true)
    end

    it 'retorna false e registra aviso, sem levantar, quando as tabelas connecta_* não existem' do
      connection = ActiveRecord::Base.connection
      allow(connection).to receive(:data_source_exists?).and_return(false)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.install!).to be(false)
      expect(Rails.logger).to have_received(:warn).with(/Connecta runtime not installed: tables missing/)
    end

    it 'aponta os modelos Scope para as tabelas de produto' do
      described_class.install!

      described_class::TABLES.each do |model, table|
        expect(model.table_name).to eq(table)
      end
    end

    it 'não muta o validador de estado do modelo Scope' do
      described_class.install!
      validator = Connecta::Scope::ConversationScope.validators_on(:state).find do |item|
        item.is_a?(ActiveModel::Validations::InclusionValidator)
      end

      expect(validator.options[:in]).to eq(Connecta::Scope::ConversationScope::STATES)
      expect(validator.options[:in]).to be_frozen
    end
  end

  describe 'estados do modelo de produto' do
    before { described_class.install! }

    it 'aceita todos os estados de produto' do
      Connecta::ConversationScope::STATES.each do |state|
        scope = Connecta::ConversationScope.new(state: state)
        scope.valid?

        expect(scope.errors[:state]).to be_empty, "estado #{state} deveria ser aceito"
      end
    end

    it 'rejeita estado inválido' do
      scope = Connecta::ConversationScope.new(state: 'bogus')
      scope.valid?

      expect(scope.errors[:state]).not_to be_empty
    end
  end
end
