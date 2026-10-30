class Connecta::Runtime::Feature
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('CONNECTA_HUMAN_NUMBER_ENABLED', 'false'))
  end

  def self.current_account_id!
    account_id = Integer(ENV.fetch('CONNECTA_ACCOUNT_ID'))
    raise ArgumentError, 'CONNECTA_ACCOUNT_ID must be positive' unless account_id.positive?

    account_id
  rescue KeyError, ArgumentError
    raise ArgumentError, 'CONNECTA_ACCOUNT_ID is required'
  end
end
