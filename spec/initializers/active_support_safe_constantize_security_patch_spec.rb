require 'rails_helper'

RSpec.describe ActiveSupport::Inflector do
  describe '.safe_constantize' do
    it 'matches autoload errors literally when the requested name contains regexp syntax' do
      requested_name = 'Example.Channel::Nested'
      error = LoadError.new('Unable to autoload constant ExampleXChannel')

      allow(described_class).to receive(:constantize).with(requested_name).and_raise(error)

      expect { requested_name.safe_constantize }.to raise_error(LoadError, error.message)
    end

    it 'returns nil when an autoload error names the missing first constant segment' do
      requested_name = 'Example.Channel::Nested'
      error = LoadError.new('Unable to autoload constant Example.Channel')

      allow(described_class).to receive(:constantize).with(requested_name).and_raise(error)

      expect(requested_name.safe_constantize).to be_nil
    end

    it 'preserves normal constant lookup behavior' do
      expect('String'.safe_constantize).to be(String)
      expect('MissingSecurityPatchConstant'.safe_constantize).to be_nil
    end
  end
end
