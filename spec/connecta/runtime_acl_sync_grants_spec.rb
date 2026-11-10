require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

# B3 (lápide de grant) + Q7.5 (foto no re-vínculo): eventos do contrato de fio
# v1 §8 (WP→fork) com os campos novos `grant_id` (uuid do staff_grant do WP) e
# `active_grant_ids`. Eventos legados sem os campos mantêm o comportamento.
RSpec.describe Connecta::Runtime::AclSyncService, 'grant tombstone + snapshot' do
  let(:service) { described_class.new }
  let(:org) { Connecta::OrgUnit.create!(name: 'Setor', path: "/setor-#{SecureRandom.hex(3)}/") }
  let(:user_id) { 900_001 }
  let(:grant_id) { SecureRandom.uuid }
  let(:projection) { { version: 1 } }

  def sync(events)
    projection[:version] += 1
    service.call({ 'projection_version' => projection[:version], 'events' => events })
  end

  def grant_upsert(overrides = {})
    { 'type' => 'grant.upsert',
      'data' => { 'chatwoot_user_id' => user_id, 'org_unit_id' => org.id, 'permission' => 'atender',
                  'version' => 1, 'epoch' => 1 }.merge(overrides) }
  end

  def grant_revoke(overrides = {})
    { 'type' => 'grant.revoke', 'data' => { 'chatwoot_user_id' => user_id }.merge(overrides) }
  end

  def link_upsert(overrides = {})
    { 'type' => 'link.upsert', 'data' => { 'chatwoot_user_id' => user_id, 'epoch' => 2 }.merge(overrides) }
  end

  before do
    Connecta::RevokedGrant.delete_all
    Connecta::UserGrant.delete_all
    Connecta::UserAuthEpoch.delete_all
    Connecta::AclSyncState.delete_all
    Connecta::AclSyncState.create!(id: 1, last_version: 1, last_heartbeat_at: Time.current)
  end

  it 'evento legado sem grant_id mantém o comportamento (cria e revoga pela trinca)' do
    expect(sync([grant_upsert])[:status]).to eq(:applied)
    grant = Connecta::UserGrant.find_by!(user_id: user_id)
    expect(grant.grant_id).to be_nil

    expect(sync([grant_revoke('org_unit_id' => org.id, 'permission' => 'atender')])[:status]).to eq(:applied)
    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(0)
    expect(Connecta::RevokedGrant.count).to eq(0)
  end

  it 'grant.revoke com grant_id apaga a linha e grava a lápide' do
    sync([grant_upsert('grant_id' => grant_id)])

    result = sync([grant_revoke('org_unit_id' => org.id, 'permission' => 'atender', 'grant_id' => grant_id)])

    expect(result[:status]).to eq(:applied)
    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(0)
    expect(Connecta::RevokedGrant.find_by!(grant_id: grant_id).revoked_at).not_to be_nil
  end

  it 'lápide ignora upsert tardio do mesmo grant_id (sem ressuscitar, sync aplicado)' do
    sync([grant_upsert('grant_id' => grant_id)])
    sync([grant_revoke('org_unit_id' => org.id, 'permission' => 'atender', 'grant_id' => grant_id)])

    result = sync([grant_upsert('grant_id' => grant_id, 'version' => 1)])

    expect(result[:status]).to eq(:applied)
    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(0)
  end

  it 'revogação com grant_id é idempotente (repete sem erro nem lápide nova)' do
    sync([grant_upsert('grant_id' => grant_id)])
    first = sync([grant_revoke('grant_id' => grant_id)])
    revoked_at = Connecta::RevokedGrant.find_by!(grant_id: grant_id).revoked_at

    second = sync([grant_revoke('grant_id' => grant_id)])

    expect(first[:status]).to eq(:applied)
    expect(second[:status]).to eq(:applied)
    expect(Connecta::RevokedGrant.find_by!(grant_id: grant_id).revoked_at.to_i).to eq(revoked_at.to_i)
  end

  it 'upsert com grant_id adota a linha legada da mesma trinca (sem duplicar)' do
    sync([grant_upsert])

    sync([grant_upsert('grant_id' => grant_id)])

    rows = Connecta::UserGrant.where(user_id: user_id, org_unit_id: org.id, permission: 'atender')
    expect(rows.count).to eq(1)
    expect(rows.first.grant_id).to eq(grant_id)
  end

  it 'revogação com grant_id limpa a linha legada da mesma trinca' do
    sync([grant_upsert])
    stale = Connecta::UserGrant.find_by!(user_id: user_id)
    expect(stale.grant_id).to be_nil

    sync([grant_revoke('org_unit_id' => org.id, 'permission' => 'atender', 'grant_id' => grant_id)])

    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(0)
  end

  it 'link.upsert com active_grant_ids remove grants obsoletos e legados, mantém os listados' do
    other_org = Connecta::OrgUnit.create!(name: 'Outro', path: "/outro-#{SecureRandom.hex(3)}/")
    kept_id = SecureRandom.uuid
    dropped_id = SecureRandom.uuid
    sync([grant_upsert('grant_id' => kept_id)])
    sync([{ 'type' => 'grant.upsert',
            'data' => { 'chatwoot_user_id' => user_id, 'org_unit_id' => other_org.id, 'permission' => 'atender',
                        'version' => 1, 'epoch' => 1, 'grant_id' => dropped_id } }])
    sync([grant_upsert('org_unit_id' => other_org.id, 'permission' => 'acompanhar')])
    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(3)

    result = sync([link_upsert('active_grant_ids' => [kept_id])])

    expect(result[:status]).to eq(:applied)
    expect(Connecta::UserGrant.where(user_id: user_id).pluck(:grant_id)).to contain_exactly(kept_id)
  end

  it 'link.upsert sem active_grant_ids mantém os grants (comportamento atual)' do
    sync([grant_upsert('grant_id' => grant_id)])
    sync([grant_upsert('permission' => 'acompanhar')])

    sync([link_upsert])

    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(2)
  end

  it 'link.upsert com foto vazia remove todos os grants do usuário' do
    sync([grant_upsert('grant_id' => grant_id)])

    sync([link_upsert('active_grant_ids' => [])])

    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(0)
  end

  it 'link.upsert com epoch velho não aplica a foto (evento obsoleto)' do
    sync([link_upsert('epoch' => 5)])
    sync([grant_upsert('grant_id' => grant_id, 'epoch' => 5)])

    sync([{ 'type' => 'link.upsert',
            'data' => { 'chatwoot_user_id' => user_id, 'epoch' => 4, 'active_grant_ids' => [] } }])

    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(1)
    expect(Connecta::UserAuthEpoch.find_by!(user_id: user_id).epoch).to eq(5)
  end

  it 'revoga e re-vincula com foto: grant fora da lista não ressuscita' do
    sync([link_upsert('epoch' => 1)])
    sync([grant_upsert('grant_id' => grant_id, 'epoch' => 1)])
    sync([{ 'type' => 'link.revoke', 'data' => { 'chatwoot_user_id' => user_id, 'epoch' => 2 } }])
    expect(Connecta::UserAuthEpoch.find_by!(user_id: user_id).revoked_locally_at).not_to be_nil

    sync([link_upsert('epoch' => 3, 'active_grant_ids' => [])])

    record = Connecta::UserAuthEpoch.find_by!(user_id: user_id)
    expect(record.revoked_locally_at).to be_nil
    expect(Connecta::UserGrant.where(user_id: user_id).count).to eq(0)
  end

  it 'active_grant_ids fora do contrato rejeita o sync (422 no controller)' do
    expect do
      sync([link_upsert('active_grant_ids' => 'nao-e-lista')])
    end.to raise_error(Connecta::Runtime::AclSyncService::InvalidProjection)
  end
end
