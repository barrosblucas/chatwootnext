# Prepend em Api::V1::Accounts::BulkActionsController (instalado só pelo spike G0), antes de enfileirar o job.
# O job filtra só leitura (PermissionFilterService) e responde 200 sem checar escrita: aqui todos os alvos são validados antes.
# Um alvo sem leitura faz tudo falhar (404); um alvo sem escrita também (403). Nada é enfileirado com sucesso parcial.
# team_id é proibido na inbox marcada (T0.2-c6, parte a): com escrita autorizada em todo alvo marcado, presença do
# parâmetro (inclusive null/mesmo valor, inclusive aninhado) vira 422 antes de enfileirar; lote misto não aplica nada.
module Connecta::Scope::BulkHook
  private

  def connecta_scope_bulk_guard!
    return unless current_user

    case params[:type].to_s.camelize
    when 'Conversation' then connecta_scope_bulk_conversations!
    when 'Contact' then connecta_scope_bulk_contacts!
    end
  end

  def connecta_scope_bulk_conversations!
    targets = Current.account.conversations.where(display_id: Array(params[:ids]), inbox_id: Connecta::Scope::Projection.marked_inbox_ids)
    return if targets.none?

    gate = Connecta::Scope::Gate.new(current_user)
    raise Connecta::Scope::Denied, :not_found unless targets.all? { |conversation| gate.read?(conversation, access_path: 'bulk_conversation') }
    raise Connecta::Scope::Denied, :forbidden unless targets.all? { |conversation| gate.write?(conversation, access_path: 'bulk_conversation') }
    raise Connecta::Scope::Denied, :unprocessable_entity if connecta_scope_bulk_team_param?
  end

  def connecta_scope_bulk_team_param?
    payload = params.to_unsafe_h
    connecta_scope_bulk_deep_key?(payload['fields'], 'team_id') || connecta_scope_bulk_deep_key?(payload, 'team_id')
  end

  def connecta_scope_bulk_deep_key?(node, key)
    case node
    when Hash
      node.any? { |k, v| k.to_s == key || connecta_scope_bulk_deep_key?(v, key) }
    when Array
      node.any? { |element| connecta_scope_bulk_deep_key?(element, key) }
    else
      false
    end
  end

  # Contato vinculado é global: nenhuma ação em lote de contato (rótulo ou exclusão) é liberada para ele.
  def connecta_scope_bulk_contacts!
    linked = Current.account.contacts.where(id: Array(params[:ids])).where(id: Connecta::Scope::ContactVisibility.linked_ids)
    raise Connecta::Scope::Denied, :forbidden if linked.exists?
  end
end
