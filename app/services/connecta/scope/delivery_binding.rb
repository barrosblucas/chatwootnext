# Captura o contexto no momento do enqueue e preserva-o durante retry/serialização.
module Connecta::Scope::DeliveryBinding
  def enqueue(options = {})
    unless @connecta_scope_captured
      @connecta_scope_context = connecta_scope_capture || { 'v' => 1, 'kind' => 'unbound' }
      @connecta_scope_captured = true
    end
    super
  end

  def serialize
    super.tap { |data| data['connecta_scope'] = @connecta_scope_context if @connecta_scope_context }
  end

  def deserialize(job_data)
    super
    @connecta_scope_context = job_data['connecta_scope']
    @connecta_scope_captured = true
    self
  end
end
