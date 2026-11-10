class Connecta::Provisioning::AgentProvisioner
  class ProvisionRejected < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason.to_s
      super("provision_rejected: #{@reason}")
    end
  end

  class NotAgent < StandardError; end

  class InvalidPassword < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason.to_s
      super("invalid_password: #{@reason}")
    end
  end

  MIN_PASSWORD_LENGTH = 12
  MAX_PASSWORD_LENGTH = 128

  # Devise (secure_password) exige ao menos 1 maiúscula, 1 minúscula, 1 dígito
  # e 1 especial; base58 nunca tem especial, então o prefixo garante as 4 classes.
  def self.generate_password
    "Aa1!#{SecureRandom.base58(28)}"
  end

  def initialize(account:)
    @account = account
  end

  # Provisiona (ou reativa) um agente: encontra ou cria o User, garante o
  # AccountUser como agent (sem nunca alterar o papel de um vínculo existente)
  # e garante InboxMember nas caixas sob enforcement do Connecta.
  # Retorna hash com ids/flags para o contrato de fio v1.
  def provision!(email:, name:, password:)
    normalized_email = normalize_email!(email)
    validate_name!(name)

    user, user_created = find_or_create_user!(normalized_email, name, password)
    check_saml_multi_account!(user)
    membership, membership_created = ensure_agent_membership!(user)
    inbox_ids_added = ensure_scoped_inbox_memberships!(user)

    {
      chatwoot_user_id: user.id,
      user_created: user_created,
      membership_created: membership_created,
      role: membership.role,
      inbox_ids_added: inbox_ids_added
    }
  end

  # Troca a senha de um agente do vínculo. Alvos administrator são recusados
  # (NotAgent) e a sessão/token anterior é invalidada.
  def set_password!(user_id:, password:)
    membership = AccountUser.find_by(account_id: @account.id, user_id: user_id)
    raise ActiveRecord::RecordNotFound, 'membership not found' if membership.nil?
    raise NotAgent, 'user is administrator' if membership.administrator?

    unless password.is_a?(String) && password.length.between?(MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH)
      raise InvalidPassword, "password must be #{MIN_PASSWORD_LENGTH}..#{MAX_PASSWORD_LENGTH} characters"
    end

    user = membership.user
    user.password = password
    user.password_confirmation = password
    user.skip_confirmation! unless user.confirmed?
    user.tokens = {}
    begin
      user.save!
    rescue ActiveRecord::RecordInvalid => e
      raise ProvisionRejected, e.record.errors.full_messages.to_sentence
    end

    true
  end

  # Desativa o vínculo: remove InboxMembers das caixas da conta, remove a
  # configuração de notificação da conta (senão o after_create do próximo
  # AccountUser estoura a unicidade e a reativação via provision dá 500),
  # destrói o AccountUser e invalida tokens. Nunca remove o User. Retorna true
  # quando desativou, false quando o vínculo já não existia (idempotente).
  def deactivate!(user_id:)
    membership = AccountUser.find_by(account_id: @account.id, user_id: user_id)
    return false if membership.nil?
    raise NotAgent, 'user is administrator' if membership.administrator?

    user = membership.user
    user.inbox_members.where(inbox_id: @account.inboxes.select(:id)).destroy_all
    user.notification_settings.where(account_id: @account.id).destroy_all
    membership.destroy!
    user.update!(tokens: {})

    true
  end

  private

  def normalize_email!(email)
    normalized = email.to_s.strip.downcase
    raise ProvisionRejected, 'email is required' if normalized.blank?

    normalized
  end

  def validate_name!(name)
    raise ProvisionRejected, 'name is required' if name.to_s.strip.blank?
  end

  def find_or_create_user!(email, name, password)
    existing = User.from_email(email)
    return [existing, false] if existing

    user = User.new(name: name.to_s.strip, email: email, password: password.presence || self.class.generate_password)
    user.skip_confirmation!
    begin
      user.save!
    rescue ActiveRecord::RecordInvalid => e
      raise ProvisionRejected, e.record.errors.full_messages.to_sentence
    end

    [user, true]
  end

  def ensure_agent_membership!(user)
    membership = AccountUser.find_by(account_id: @account.id, user_id: user.id)
    return [membership, false] if membership

    begin
      membership = AccountUser.create!(account: @account, user: user, role: :agent)
    rescue ActiveRecord::RecordInvalid => e
      raise ProvisionRejected, e.record.errors.full_messages.to_sentence
    end

    [membership, true]
  end

  # Caixas da conta marcadas no Connecta sob enforcement (exclui admin_only,
  # que nega superfície a não-admin, e maintenance). Espelha o recorte de
  # `conversation_query.rb:59` (human send).
  def scoped_inbox_ids
    Inbox.where(account_id: @account.id)
         .joins('INNER JOIN connecta_scoped_inboxes ON connecta_scoped_inboxes.inbox_id = inboxes.id')
         .where.not(connecta_scoped_inboxes: { enforcement: 'admin_only' })
         .where(connecta_scoped_inboxes: { maintenance: false })
         .pluck(:id)
  end

  def ensure_scoped_inbox_memberships!(user)
    added = []
    scoped_inbox_ids.each do |inbox_id|
      member = InboxMember.find_or_create_by!(inbox_id: inbox_id, user_id: user.id)
      added << inbox_id if member.previously_new_record?
    rescue ActiveRecord::RecordNotUnique
      nil
    end
    added
  end

  # Espelha `enterprise/agent_builder.rb:validate_saml_invitation!`: com SAML
  # ligado na conta, um usuário já vinculado a outras contas não pode entrar.
  def check_saml_multi_account!(user)
    return unless @account.respond_to?(:saml_enabled?) && @account.saml_enabled?
    return unless user.persisted?
    return unless user.account_users.where.not(account_id: @account.id).exists?

    raise ProvisionRejected, I18n.t('errors.saml.multi_account_invitation_not_allowed',
                                    default: 'Users associated with another account cannot be added while SAML is enabled')
  end
end
