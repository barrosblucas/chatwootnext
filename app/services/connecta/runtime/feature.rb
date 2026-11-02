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

  # Ids de usuários de serviço (ex.: o usuário do bot de triagem) autorizados a
  # enviar em conversas no estado 'reception' de inboxes marcadas. Lista de ids
  # separados por vírgula; vazia ou ausente = nada liberado (comportamento atual).
  def self.reception_sender_user_ids
    ENV.fetch('CONNECTA_RECEPTION_SENDER_USER_IDS', '').split(',').map(&:strip).filter_map do |raw|
      Integer(raw, 10)
    rescue ArgumentError
      nil
    end.select(&:positive?).uniq
  end
end
