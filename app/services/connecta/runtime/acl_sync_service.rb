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
    grant = Connecta::UserGrant.find_or_initialize_by(user_id: user_id, org_unit_id: unit_id, permission: permission)
    grant.version = integer(data['version'] || 1)
    grant.save!
    ensure_active_epoch!(user_id, data['epoch'])
  end

  def revoke_grant!(data)
    scope = Connecta::UserGrant.where(user_id: integer(data['chatwoot_user_id'] || data['user_id']))
    scope = scope.where(org_unit_id: data['org_unit_id']) if data['org_unit_id'].present?
    scope = scope.where(permission: data['permission']) if data['permission'].present?
    scope.destroy_all
  end

  def verify_link!(data)
    user_id = integer(data['chatwoot_user_id'] || data['user_id'])
    raise InvalidProjection, 'link epoch is required' if data['epoch'].nil?

    epoch = integer(data['epoch'])
    record = Connecta::UserAuthEpoch.find_or_initialize_by(user_id: user_id)
    return if record.epoch > epoch || (record.revoked_locally_at.present? && record.epoch >= epoch)

    record.update!(epoch: epoch, revoked_locally_at: nil, source: 'platform')
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
