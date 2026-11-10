class Connecta::Runtime::AclSyncService
  class InvalidProjection < StandardError; end

  # Contrato de fio v1 §8: também é heartbeat — events vazio atualiza o heartbeat
  # da ACL. Versão velha é ignorada sem renovar o heartbeat (não torna a projeção fresh).
  # Validação de payload e transação de sync em um ponto; dividir não muda o contrato de heartbeat.
  def call(payload) # rubocop:disable Metrics/CyclomaticComplexity
    version = integer(payload['projection_version'] || payload['version'])
    events = payload['events']
    raise InvalidProjection, 'projection_version must be non-negative' if version.negative?
    raise InvalidProjection, 'events must be an array' unless events.is_a?(Array)

    result = :applied
    Connecta::AclSyncState.transaction do
      state = Connecta::AclSyncState.lock.find_or_initialize_by(id: 1)
      if version < state.last_version
        result = :stale
        next
      end

      events.each { |event| apply_event!(event) }
      state.last_version = version
      # A valid signed sync request is the heartbeat; stale requests cannot make the projection fresh.
      state.last_heartbeat_at = Time.current
      state.save!
    end

    { status: result, version: Connecta::AclSyncState.order(:id).first&.last_version || 0 }
  end

  private

  # Despacho de tipos de evento do contrato v1 §8 (um case por tipo, sem lógica própria).
  def apply_event!(event) # rubocop:disable Metrics/CyclomaticComplexity
    raise InvalidProjection, 'event must be an object' unless event.is_a?(Hash)

    type = event['type'].to_s
    data = event['data']
    raise InvalidProjection, 'event data must be an object' unless data.is_a?(Hash)

    case type
    when 'org.upsert' then upsert_org_unit!(data)
    when 'org.delete' then disable_org_unit!(data)
    when 'grant.upsert' then upsert_grant!(data)
    when 'grant.revoke' then revoke_grant!(data)
    when 'link.upsert' then verify_link!(data)
    when 'link.revoke', 'user.epoch' then revoke_link!(data)
    else
      raise InvalidProjection, "unknown ACL event: #{type}"
    end
  end

  def upsert_org_unit!(data)
    id = required(data, 'id')
    unit = Connecta::OrgUnit.find_or_initialize_by(id: id)
    unit.assign_attributes(
      name: required(data, 'name'), parent_id: data['parent_id'], path: required(data, 'path'),
      enabled: data.fetch('enabled', true), version: integer(data['version'] || 1)
    )
    unit.save!
  end

  # update_all: desativação em massa por id, sem callbacks de validação; a ACL é a fonte da verdade.
  def disable_org_unit!(data)
    Connecta::OrgUnit.where(id: required(data, 'id')).update_all(enabled: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def upsert_grant!(data)
    user_id = integer(data['chatwoot_user_id'] || data['user_id'])
    unit_id = required(data, 'org_unit_id')
    permission = required(data, 'permission')
    grant_id = data['grant_id'].to_s.presence
    # Lápide B3: grant revogado não ressuscita por replay/atraso do WP.
    return if grant_id && Connecta::RevokedGrant.exists?(grant_id: grant_id)
    # Trinca lapidada: upsert legado (sem grant_id) é replay e é ignorado;
    # upsert com grant_id novo é re-concessão legítima (limpa a lápide).
    return if legacy_tombstoned_grant?(user_id, unit_id, permission, grant_id)

    # Busca pela trinca (não pelo grant_id): adota a linha legada da era
    # pré-grant_id em vez de duplicá-la e violar a unicidade da trinca.
    grant = Connecta::UserGrant.find_or_initialize_by(user_id: user_id, org_unit_id: unit_id, permission: permission)
    grant.grant_id = grant_id if grant_id
    grant.version = integer(data['version'] || 1)
    grant.save!
    ensure_active_epoch!(user_id, data['epoch'])
  end

  def revoke_grant!(data)
    user_id = integer(data['chatwoot_user_id'] || data['user_id'])
    grant_id = data['grant_id'].to_s.presence
    if grant_id
      revoke_grant_by_id!(user_id, data, grant_id)
      return
    end

    scope = Connecta::UserGrant.where(user_id: user_id)
    scope = scope.where(org_unit_id: data['org_unit_id']) if data['org_unit_id'].present?
    scope = scope.where(permission: data['permission']) if data['permission'].present?
    scope.destroy_all
  end

  # Revogação com grant_id: apaga a linha do grant, a linha legada da mesma
  # trinca (criada antes do WP enviar grant_id) quando a trinca vem completa,
  # e grava a lápide do grant_id mais a lápide da trinca (para que um upsert
  # legado tardio, sem grant_id, seja ignorado).
  def revoke_grant_by_id!(user_id, data, grant_id)
    triple = triple_present?(data)
    scope = Connecta::UserGrant.where(user_id: user_id)
    if triple
      scope = scope.where(org_unit_id: data['org_unit_id'], permission: data['permission'])
      scope = scope.where('grant_id = ? OR grant_id IS NULL', grant_id)
    else
      scope = scope.where(grant_id: grant_id)
    end
    scope.destroy_all
    tombstone = Connecta::RevokedGrant.find_or_initialize_by(grant_id: grant_id)
    tombstone.revoked_at ||= Time.current
    if triple
      tombstone.user_id = user_id
      tombstone.org_unit_id = data['org_unit_id']
      tombstone.permission = data['permission']
    end
    tombstone.save!
  end

  def triple_present?(data)
    data['org_unit_id'].present? && data['permission'].present?
  end

  def triple_tombstoned?(user_id, unit_id, permission)
    Connecta::RevokedGrant.exists?(user_id: user_id, org_unit_id: unit_id, permission: permission)
  end

  # Decide o veto da trinca lapidada: com grant_id novo, limpa a lápide da
  # trinca (re-concessão legítima) e libera; sem grant_id, veta (replay legado).
  def legacy_tombstoned_grant?(user_id, unit_id, permission, grant_id)
    if grant_id
      clear_triple_tombstone!(user_id, unit_id, permission)
      return false
    end

    triple_tombstoned?(user_id, unit_id, permission)
  end

  def clear_triple_tombstone!(user_id, unit_id, permission)
    # Limpa só a trinca (mantém as lápides por grant_id: um upsert tardio com
    # um grant_id antigo ainda é ignorado pela checagem B3).
    scope = Connecta::RevokedGrant.where(user_id: user_id, org_unit_id: unit_id, permission: permission)
    scope.update_all(user_id: nil, org_unit_id: nil, permission: nil, # rubocop:disable Rails/SkipsModelValidations
                     updated_at: Time.current)
  end

  def verify_link!(data)
    user_id = integer(data['chatwoot_user_id'] || data['user_id'])
    raise InvalidProjection, 'link epoch is required' if data['epoch'].nil?

    epoch = integer(data['epoch'])
    record = Connecta::UserAuthEpoch.find_or_initialize_by(user_id: user_id)
    return if stale_link?(record, epoch)

    record.update!(epoch: epoch, revoked_locally_at: nil, source: 'platform')
    apply_snapshot_if_present!(user_id, data)
  end

  # Evento obsoleto: época menor que a registrada, ou época igual quando o
  # vínculo já foi revogado localmente (a revogação vence o empate).
  def stale_link?(record, epoch)
    return true if record.epoch > epoch

    record.revoked_locally_at.present? && record.epoch >= epoch
  end

  # Foto Q7.5: com a lista de grants ativos do WP, apaga os grants obsoletos
  # do usuário (fora da lista ou legados sem grant_id) para que o re-vínculo
  # não ressuscite acesso já removido. Sem a lista, mantém o comportamento.
  def apply_snapshot_if_present!(user_id, data)
    return unless data.key?('active_grant_ids') && !data['active_grant_ids'].nil?

    apply_grant_snapshot!(user_id, data['active_grant_ids'])
  end

  def apply_grant_snapshot!(user_id, active_grant_ids)
    raise InvalidProjection, 'active_grant_ids must be an array' unless active_grant_ids.is_a?(Array)

    base = Connecta::UserGrant.where(user_id: user_id)
    doomed = if active_grant_ids.empty?
               base
             else
               listed = active_grant_ids.map(&:to_s)
               base.where.not(grant_id: listed).or(base.where(grant_id: nil))
             end
    doomed.destroy_all
  end

  def revoke_link!(data)
    user_id = integer(data['chatwoot_user_id'] || data['user_id'])
    epoch = integer(data['epoch'])
    record = Connecta::UserAuthEpoch.find_or_initialize_by(user_id: user_id)
    return if record.epoch > epoch

    record.update!(epoch: epoch, revoked_locally_at: Time.current, source: 'platform')
  end

  def ensure_active_epoch!(user_id, value)
    return if value.nil?

    epoch = integer(value)
    record = Connecta::UserAuthEpoch.find_or_initialize_by(user_id: user_id)
    return if record.epoch > epoch || record.revoked_locally_at.present?

    record.update!(epoch: epoch, source: 'platform')
  end

  def required(data, key)
    value = data[key]
    raise InvalidProjection, "#{key} is required" if value.blank?

    value
  end

  def integer(value)
    Integer(value)
  rescue ArgumentError, TypeError
    raise InvalidProjection, 'expected an integer'
  end
end
