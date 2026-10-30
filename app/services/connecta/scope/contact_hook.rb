# Prepend em Api::V1::Accounts::ContactsController (instalado só pelo spike G0).
# Listagens (index, search, active, filter) e leitura por id só mostram contatos visíveis; escrita em contato vinculado é negada (403).
# Export de contatos fica negado enquanto houver inbox marcada, antes de enfileirar o job.
# RF2 (spike G0): after_action so no prepend (base nativa NÃO editada) redige DTOs de contato marcado para leitor
# só escopado — custom_attributes/notas globais fora, nome/telefone/id preservados; unmarked/admin nativo.
module Connecta::Scope::ContactHook
  def self.prepended(base)
    base.after_action :connecta_scope_redact_contact_response!,
                      only: %i[index show search active filter]
  end

  # POST contacts com inbox_id marcada (spike G0): só admin nominal da projeção cria o vínculo, depois da
  # autenticação/conta carregadas e ANTES de persistir o contato, mesclar/upsert ou chamar o provedor.
  # Membro com grant atender/acompanhar sozinho NÃO está autorizado (403): criação com inbox física marcada é
  # provisionamento no inbox global, sem conversa/etapa para determinar setor. Admin nominal não escapa a policy
  # nativa (ContactPolicy#create?), a validade/epoch do regime inbox guard (UserAuthEpoch/freshness) nem a conta
  # da inbox (foreign account NÃO chega a persistência/provedor). Generic create NOVO sem inbox_id e unmarked
  # seguem nativos: nenhum builder/model global guard (entrada do cidadão deve continuar).
  # `create` é público no prepend para alcançar `super`; o fluxo nativo de before_action NÃO é tocado.
  def create
    connecta_scope_contact_create_guard!
    super
  end

  private

  # RF2 (spike G0, test-only): apos o render nativo, redige SOMENTE DTOs de contato nas acoes de
  # leitura index/show/search/active/filter. Contato marcado para usuario SO escopado (sem admin
  # nominal real via Projection#admin?): remove custom_attributes/notas globais do JSON ja
  # renderizado, mantendo nome/telefone/id. Unmarked segue nativo; admin/negados seguem nativos
  # (403 escrita, 404 leitura de vinculado e NotesHook intactos). Nunca toca Conversation/protocolo
  # embutido: atua so por ids de contato carregados na acao; sem recursao cega por chave.
  def connecta_scope_redact_contact_response!
    return unless connecta_scope_redactable_response?

    restricted_ids = connecta_scope_restricted_response_ids
    return if restricted_ids.empty?

    body = JSON.parse(response.body)
    connecta_scope_redact_contact_payload!(body['payload'], restricted_ids)
    response.body = body.to_json
  rescue JSON::ParserError
    nil
  end

  def connecta_scope_redactable_response?
    response.media_type == 'application/json' && !current_user.nil? &&
      connecta_scope_response_contacts.any?
  end

  def connecta_scope_restricted_response_ids
    connecta_scope_response_contacts.select do |contact|
      Connecta::Scope::ContactDataProjection.restricted_contact?(contact, current_user)
    end.map(&:id)
  end

  # Localiza DTOs de contato pela estrutura nativa de cada acao coberta: show exibe
  # payload unico (@contact); index/search/active/filter exibem payload como lista
  # (@contacts). O create RF3 responde payload.contact + payload.contact_inbox e NAO
  # passa por este after_action (only acima). Sem recursao por chave em Conversation.
  def connecta_scope_response_contacts
    contacts = []
    contacts.concat(Array(@contacts)) if defined?(@contacts) && !@contacts.nil?
    contacts << @contact if defined?(@contact) && !@contact.nil?
    contacts.select { |record| record.is_a?(::Contact) }
  end

  def connecta_scope_redact_contact_payload!(payload, restricted_ids)
    case payload
    when Array
      payload.each { |entry| connecta_scope_redact_contact_entry!(entry, restricted_ids) if entry.is_a?(Hash) }
    when Hash
      connecta_scope_redact_contact_entry!(payload, restricted_ids)
    end
  end

  def connecta_scope_redact_contact_entry!(entry, restricted_ids)
    return unless restricted_ids.include?(entry['id'])

    redacted = Connecta::Scope::ContactDataProjection.redact_contact(entry)
    entry.replace(redacted)
  end

  def fetch_contact
    super
    Connecta::Scope::ContactVisibility.guard!(@contact, current_user, account: Current.account, read: request.get?)
  end

  # Roda como parte do create sobrescrito. Sem inbox_id: nativo. Inbox não marcada: nativo. Autenticação/conta
  # carregadas vêm antes (before_action nativos: set_current_user, current_account, check_authorization).
  def connecta_scope_contact_create_guard!
    return if params[:inbox_id].blank? || current_user.nil?
    return unless Connecta::Scope::Projection.marked?(params[:inbox_id])

    connecta_scope_contact_create_marked_guard!
  rescue ActiveRecord::RecordNotFound
    connecta_scope_contact_create_deny!(:not_found)
  end

  def connecta_scope_contact_create_marked_guard!
    Current.account.inboxes.find(params[:inbox_id])
    native_admin = Current.account_user&.administrator?
    nominal = Connecta::Scope::Projection.new(current_user).admin?
    raise Connecta::Scope::Denied, :forbidden unless nominal && native_admin

    connecta_scope_contact_create_allow!
  rescue Connecta::Scope::Denied => e
    connecta_scope_contact_create_deny!(e.status)
  end

  def connecta_scope_contact_create_allow!
    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'contact',
                                         access_path: 'contact_create', decision: 'allow')
  end

  def connecta_scope_contact_create_deny!(status)
    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'contact',
                                         access_path: 'contact_create', decision: 'deny')
    raise Connecta::Scope::Denied, status
  end

  def fetch_contacts(contacts)
    super(visible_contacts(contacts))
  end

  def fetch_contacts_with_has_more(contacts)
    super(visible_contacts(contacts))
  end

  def visible_contacts(contacts)
    contacts.where(id: Connecta::Scope::ContactVisibility.visible_scope(Current.account, current_user).select(:id))
  end

  def connecta_scope_export_guard!
    return if Connecta::Scope::Projection.marked_inbox_ids.empty?

    Connecta::Scope::AccessAudit.create!(user_id: current_user.id, conversation_id: nil, surface: 'contact',
                                         access_path: 'contacts_export', decision: 'deny')
    raise Connecta::Scope::Denied, :forbidden
  end
end
