# Fixture do spike G0 (T0.2): dois setores (A e B) na MESMA inbox WhatsApp, inbox de controle nativa e atores reais com grants.
# Compartilhada pelos specs de escopo. Nenhuma decisão de autorização ou resultado de consulta é mockado.
# O fixture tem ~30 entidades explícitas; o limite padrão de helpers não se aplica aqui.
# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/LetSetup
# Os let! criam entidades que os specs que incluem o contexto usam por nome (conv_orphan, marked_inbox etc.).
RSpec.shared_context 'with connecta g0 scope fixture' do
  let(:json) { JSON.parse(response.body) }
  let(:conversations_path) { "/api/v1/accounts/#{account.id}/conversations" }

  let!(:account) { create(:account) }
  # Provedor Baileys sem rede: a validação de credenciais (GET /status/auth) não faz parte do spike, então o canal é gravado sem validar.
  let!(:whatsapp_channel) do
    build(:channel_whatsapp, account: account, provider: 'baileys').tap { |channel| channel.save!(validate: false) }
  end
  let!(:whatsapp_inbox) do
    build(:inbox, account: account, channel: whatsapp_channel, name: 'WhatsApp Baileys').tap { |inbox| inbox.save!(validate: false) }
  end
  let!(:control_inbox) { create(:inbox, account: account) }

  let!(:agent_a) { create(:user, account: account, role: :agent) }
  let!(:agent_b) { create(:user, account: account, role: :agent) }
  let!(:manager_a) { create(:user, account: account, role: :agent) }
  let!(:member_without_grant) { create(:user, account: account, role: :agent) }
  let!(:admin_nominal) { create(:user, account: account, role: :agent) }

  let!(:org_root) { Connecta::Scope::OrgUnit.create!(name: 'Raiz', path: '/raiz/') }
  let!(:org_a) { Connecta::Scope::OrgUnit.create!(name: 'Setor A', path: '/raiz/a/', parent: org_root) }
  let!(:org_a1) { Connecta::Scope::OrgUnit.create!(name: 'Sub A1', path: '/raiz/a/a1/', parent: org_a) }
  let!(:org_b) { Connecta::Scope::OrgUnit.create!(name: 'Setor B', path: '/raiz/b/', parent: org_root) }

  let!(:contact_a) { create(:contact, account: account) }
  let!(:contact_a1) { create(:contact, account: account) }
  let!(:contact_b) { create(:contact, account: account) }
  let!(:contact_transferred) { create(:contact, account: account) }
  let!(:contact_orphan) { create(:contact, account: account) }
  let!(:contact_control) { create(:contact, account: account) }

  let!(:conv_a) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_a) }
  let!(:conv_a1) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_a1) }
  let!(:conv_b) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_b) }
  let!(:conv_transferred) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_transferred) }
  let!(:conv_orphan) { create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact_orphan) }
  let!(:conv_control) { create(:conversation, account: account, inbox: control_inbox, contact: contact_control) }

  let!(:marked_inbox) { Connecta::Scope::ScopedInbox.create!(inbox_id: whatsapp_inbox.id, enforcement: 'enforce', maintenance: false) }
  let!(:projection_heartbeat) { Connecta::Scope::AclSyncState.create!(last_version: 1, last_heartbeat_at: Time.current) }

  before do
    [agent_a, agent_b, manager_a, member_without_grant, admin_nominal].each do |user|
      create(:inbox_member, inbox: whatsapp_inbox, user: user)
      Connecta::Scope::UserAuthEpoch.create!(user_id: user.id, epoch: 1)
    end
    create(:inbox_member, inbox: control_inbox, user: agent_a)

    Connecta::Scope::ConversationScope.create!(conversation_id: conv_a.id, inbox_id: whatsapp_inbox.id, contact_id: contact_a.id,
                                               org_unit: org_a, state: 'active', case_protocol: 'CASO-A', case_version: 1)
    Connecta::Scope::ConversationScope.create!(conversation_id: conv_a1.id, inbox_id: whatsapp_inbox.id, contact_id: contact_a1.id,
                                               org_unit: org_a1, state: 'active', case_protocol: 'CASO-A1', case_version: 1)
    Connecta::Scope::ConversationScope.create!(conversation_id: conv_b.id, inbox_id: whatsapp_inbox.id, contact_id: contact_b.id,
                                               org_unit: org_b, state: 'active', case_protocol: 'CASO-B', case_version: 1)
    Connecta::Scope::ConversationScope.create!(conversation_id: conv_transferred.id, inbox_id: whatsapp_inbox.id,
                                               contact_id: contact_transferred.id, org_unit: org_a, state: 'transferred_out',
                                               case_protocol: 'CASO-T', case_version: 1)

    Connecta::Scope::UserGrant.create!(user_id: agent_a.id, org_unit: org_a, permission: 'atender')
    Connecta::Scope::UserGrant.create!(user_id: agent_b.id, org_unit: org_b, permission: 'atender')
    Connecta::Scope::UserGrant.create!(user_id: manager_a.id, org_unit: org_a, permission: 'acompanhar')
    Connecta::Scope::UserGrant.create!(user_id: admin_nominal.id, org_unit: org_root, permission: 'admin_nominal')
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/LetSetup
