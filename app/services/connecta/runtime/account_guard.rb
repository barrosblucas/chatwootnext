class Connecta::Runtime::AccountGuard
  def self.check!(provided, configured)
    value =
      case provided
      when Integer then provided
      when String then Integer(provided.strip)
      else raise Connecta::Runtime::AccountMismatch, 'account_id is required'
      end
    raise Connecta::Runtime::AccountMismatch, 'account_id mismatch' unless value == configured && value.positive?

    value
  rescue ArgumentError, TypeError
    raise Connecta::Runtime::AccountMismatch, 'account_id is invalid'
  end
end
