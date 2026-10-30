require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# RF3 · criação de contato com inbox marcada (spike G0): POST contacts com
# phone_number + inbox_id de inbox marcada nega antes de persistir, mesclar ou
# chamar o provedor, exceto admin nominal. Casos ESCRITOS em 2026-10-24 e NÃO
# EXECUTADOS; execução funcional pendente na validação consolidada.
# Contrato nativo (somente leitura aqui): `contacts_controller.rb:94-105`
# (create salva o contato, chama build_contact_inbox e process_avatar),
# `:184-192` (build_contact_inbox acha a inbox no Current.account e chama o
# ContactInboxBuilder com validate_baileys_phone), `contact_inbox_builder.rb`
# (normalize via on_whatsapp na shape {'exists', 'jid'}; merge quando o
# canônico já existe), `contact_policy.rb:42` (create? nativo true),
# `request_exception_handler.rb` (RecordNotFound vira 404) e rota
# `config/routes.rb:256` (POST contacts). Leitura/escrita do spike: 404 na
# leitura e 403 na escrita; create é escrita, por isso a negação do guard é
# 403 e o 404 fica reservado ao nativo (inbox de outra conta ou inexistente).
# Guard (ContactHook) escrito em frente independente; esta spec usa API pública
# nativa (HTTP real) + stub do transporte (shape nativa, sem rede). Sem Gate
# fake, sem Controller fake, sem jobs executados, sem .env/banco/migração.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · criação de contato com inbox marcada (RF3)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:contacts_path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_member) { member_without_grant.create_new_auth_token }
  let(:token_manager) { manager_a.create_new_auth_token }
  let(:token_nominal) { admin_nominal.create_new_auth_token }
  let(:native_admin) { create(:user, account: account, role: :administrator) }
  let(:token_native_admin) { native_admin.create_new_auth_token }

  # Transporte stubado na shape nativa do provedor Baileys (fallback real
  # `{'jid', 'exists' => false}`): nunca sai rede; negações provam zero
  # chamada e o positivo prova o caminho com shape real.
  # Spy real do transporte: `expect_any_instance_of` não aceita `have_received`, então cada chamada ao
  # provedor é registrada no próprio stub e a negação prova zero chamadas pela lista registrada.
  def stub_marked_provider!(exists: false, jid: '5511999990002@s.whatsapp.net')
    provider_calls.clear
    allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp) do |_channel, phone| # rubocop:disable RSpec/AnyInstance
      provider_calls << phone
      { 'exists' => exists, 'jid' => jid }
    end
  end

  def provider_calls
    @provider_calls ||= []
  end

  def expect_no_provider_call!
    expect(provider_calls).to be_empty
  end

  describe 'rota (não confundir 403/404 de ACL com rota inexistente)' do
    it 'POST contacts existe na rota nativa' do
      expect(Rails.application.routes.recognize_path(contacts_path, method: :post))
        .to include(controller: 'api/v1/accounts/contacts', action: 'create')
    end
  end

  describe 'negação antes de persistir/mesclar/provedor (marcada própria)' do
    it 'membro sem grant é negado 403 sem Contact/ContactInbox novo e sem provedor' do
      stub_marked_provider!
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Novo', phone_number: '+5511999990011', inbox_id: whatsapp_inbox.id },
           headers: token_member, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect_no_provider_call!
    end

    it 'outro setor (atender B) é negado 403 sem efeito e sem provedor' do
      stub_marked_provider!
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Setor B', phone_number: '+5511999990021', inbox_id: whatsapp_inbox.id },
           headers: token_b, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect_no_provider_call!
    end

    it 'gestor (acompanhar) é negado 403 sem efeito e sem provedor' do
      stub_marked_provider!
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Gestor', phone_number: '+5511999990022', inbox_id: whatsapp_inbox.id },
           headers: token_manager, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect_no_provider_call!
    end

    it 'atender do próprio setor sem nominal é negado 403 sem efeito e sem provedor' do
      stub_marked_provider!
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Atender', phone_number: '+5511999990023', inbox_id: whatsapp_inbox.id },
           headers: token_a, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect_no_provider_call!
    end

    it 'admin nativo sem grant nominal não ganha permissão (403, sem efeito, sem provedor)' do
      stub_marked_provider!
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Nativo', phone_number: '+5511999990024', inbox_id: whatsapp_inbox.id },
           headers: token_native_admin, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect_no_provider_call!
    end

    it 'telefone já existente não mescla nem altera o dono (403, attrs intactos, provedor zero)' do
      stub_marked_provider!
      existing = create(:contact, account: account, name: 'RF3 Dono', phone_number: '+5511999990031',
                                  custom_attributes: { 'plano' => 'basico' })
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Tentativa', phone_number: '+5511999990031', inbox_id: whatsapp_inbox.id },
           headers: token_member, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect(existing.reload.name).to eq('RF3 Dono')
      expect(existing.reload.custom_attributes).to eq('plano' => 'basico')
      expect_no_provider_call!
    end
  end

  describe 'inbox de outra conta ou inexistente (404 nativo, sem efeito)' do
    it 'inbox de outra conta nega 404 nativo sem efeito e sem provedor' do
      stub_marked_provider!
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Estrangeiro', phone_number: '+5511999990041', inbox_id: other_inbox.id },
           headers: token_a, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect_no_provider_call!
    end

    it 'inbox_id inexistente nega 404 nativo sem efeito (prova 403 ≠ 404 de rota)' do
      stub_marked_provider!
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Fantasma', phone_number: '+5511999990042', inbox_id: 999_999_999 },
           headers: token_a, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Contact.count).to eq(before_contacts)
      expect(ContactInbox.count).to eq(before_inboxes)
      expect_no_provider_call!
    end
  end

  describe 'positivos e controles (nativo preservado, sem transporte real)' do
    it 'admin nominal cria com marcada via shape nativa (200, Contact+ContactInbox)' do
      stub_marked_provider!(exists: false, jid: '5511999990002@s.whatsapp.net')
      # Guard exige admin nominal E administrador nativo (contact_hook.rb): o fixture cria o nominal como :agent.
      admin_nominal.account_users.find_by!(account: account).update!(role: :administrator)
      before_inboxes = ContactInbox.count

      expect do
        post contacts_path,
             params: { name: 'RF3 Nominal', phone_number: '+5511999990002', inbox_id: whatsapp_inbox.id },
             headers: token_nominal, as: :json
      end.to change(Contact, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(ContactInbox.count).to eq(before_inboxes + 1)
      expect(response.parsed_body.dig('payload', 'contact_inbox', 'source_id')).to eq('5511999990002')
    end

    it 'inbox própria não marcada preserva nativo (200, Contact+ContactInbox)' do
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path,
           params: { name: 'RF3 Livre', phone_number: '+5511999990051', inbox_id: control_inbox.id },
           headers: token_member, as: :json

      expect(response).to have_http_status(:ok)
      expect(Contact.count).to eq(before_contacts + 1)
      expect(ContactInbox.count).to eq(before_inboxes + 1)
    end

    it 'create genérico sem inbox_id preserva nativo (200, Contact novo, nenhum ContactInbox)' do
      before_contacts = Contact.count
      before_inboxes = ContactInbox.count

      post contacts_path, params: { name: 'RF3 Generico', email: 'rf3-generico@example.com' },
                          headers: token_member, as: :json

      expect(response).to have_http_status(:ok)
      expect(Contact.count).to eq(before_contacts + 1)
      expect(ContactInbox.count).to eq(before_inboxes)
    end
  end
end
