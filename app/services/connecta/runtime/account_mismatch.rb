class Connecta::Runtime::AccountMismatch < StandardError
  def self.check!(provided, configured)
    Connecta::Runtime::AccountGuard.check!(provided, configured)
  end
end
