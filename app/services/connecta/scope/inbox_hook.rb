# Prepend em Api::V1::Accounts::InboxesController (instalado só pelo spike G0).
# QR/sessão, conexão, webhook, agente-bot e gestão da inbox marcada são do admin nominal. Leitura da inbox (show, campanhas) segue nativa.
module Connecta::Scope::InboxHook
  NOMINAL_ACTIONS = %w[health on_whatsapp setup_channel_provider import_whatsapp_session disconnect_channel_provider convert_provider
                       sync_templates register_webhook reset_secret agent_bot set_agent_bot avatar update destroy].freeze

  class << self
    def defer_audit?(action)
      NOMINAL_ACTIONS.include?(action.to_s)
    end

    def pending_audits
      @pending_audits ||= {}
    end

    def take_pending_audit!(key)
      pending_audits.delete(key)
    end

    def audit_key_for(controller, suffix)
      :"#{controller.object_id}_#{suffix}"
    end
  end

  private

  # Fluxo coeso obrigatorio de autorizacao pos-fetch e pre-provedor + audit allow diferido:
  # fatiar espalharia gate/auditoria sem reduzir acoplamento real.
  # rubocop:disable Metrics/AbcSize
  def fetch_inbox
    super
    return if @inbox.nil? || !Connecta::Scope::Projection.marked?(@inbox.id)
    return if current_user.nil?
    return unless Connecta::Scope::InboxHook.defer_audit?(action_name)

    # Gate da inbox marcada: roda aqui (após autenticação/conta carregadas),
    # ANTES da validação nativa de payload ou de qualquer chamada ao provedor.
    # Não-admin (agente/gestor/membro) nega com 403 (GET: 404) e auditoria
    # `deny`, sem tocar no provedor. Admin nominal segue o fluxo nativo
    # (c7b: auditoria `allow` somente após autorização efetiva).
    nominal = Connecta::Scope::Projection.new(current_user).admin?
    unless nominal
      Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'inbox',
                                           access_path: "inbox_#{action_name}", decision: 'deny')
      raise Connecta::Scope::Denied, (request.get? ? :not_found : :forbidden)
    end

    Connecta::Scope::InboxHook.pending_audits[Connecta::Scope::InboxHook.audit_key_for(self, action_name)] = {
      user_id: current_user.id, access_path: "inbox_#{action_name}", inbox_id: @inbox.id
    }
  end
  # rubocop:enable Metrics/AbcSize

  def check_authorization(model = nil)
    super
    connecta_scope_flush_nominal_audit!
  rescue Pundit::NotAuthorizedError
    Connecta::Scope::InboxHook.take_pending_audit!(connecta_scope_pending_key)
    raise
  end

  def check_admin_authorization?
    super
    connecta_scope_flush_nominal_audit!
  rescue Pundit::NotAuthorizedError
    Connecta::Scope::InboxHook.take_pending_audit!(connecta_scope_pending_key)
    raise
  end

  # Criar inbox WhatsApp (sessão de número físico) também é privilégio do admin nominal. O create nativo
  # não passa por check_authorization (InboxPolicy#create? roda dentro do create): o guard nega não-admin
  # antes de qualquer I/O e só audita o allow quando o admin nominal também é administrator da conta.
  # Este guard roda como prepend_before_action, ANTES de current_account: Current.account_user ainda é nil
  # nesse ponto. Por isso o vínculo nativo é resolvido pela conta da rota (fail-closed: sem vínculo, nega).
  # Bootstrap: numa conta fresca nenhuma inbox está marcada, então Projection#admin? é impossível
  # antes do sync de ACL — o administrador nativo pode criar a primeira inbox WhatsApp (allow
  # auditado como 'inbox_create_bootstrap'). Assim que a conta tem qualquer inbox marcada,
  # vale a regra nominal de sempre.
  def connecta_scope_inbox_create_guard!
    return unless current_user && params.dig(:channel, :type) == 'whatsapp'

    native_admin = connecta_scope_native_administrator?
    if !Connecta::Scope::ScopedInbox.account_marked?(params[:account_id]) && native_admin
      Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'inbox',
                                           access_path: 'inbox_create_bootstrap', decision: 'allow')
      return
    end

    nominal = Connecta::Scope::Projection.new(current_user).admin?
    unless nominal && native_admin
      Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'inbox',
                                           access_path: 'inbox_create', decision: 'deny')
      raise Connecta::Scope::Denied, :forbidden
    end

    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'inbox',
                                         access_path: 'inbox_create', decision: 'allow')
  end

  def connecta_scope_flush_nominal_audit!
    pending = Connecta::Scope::InboxHook.take_pending_audit!(connecta_scope_pending_key)
    return if pending.nil? || pending[:user_id].nil?

    Connecta::Scope::AccessAudit.create!(user_id: pending[:user_id], conversation_id: nil, surface: 'inbox',
                                         access_path: pending[:access_path], decision: 'allow')
  end

  def connecta_scope_pending_key
    Connecta::Scope::InboxHook.audit_key_for(self, action_name)
  end

  # Administrador nativo da conta da rota, sem depender de Current.account_user (ainda não carregado neste guard).
  def connecta_scope_native_administrator?
    ::AccountUser.find_by(account_id: params[:account_id], user_id: current_user.id)&.administrator? || false
  end
end
