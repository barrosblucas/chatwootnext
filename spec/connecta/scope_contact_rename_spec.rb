require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# Correção 01: corrigir o nome de um contato vinculado a inbox marcada. Qualquer nível de usuário da
# conta (administrator nativo, agente com grant) pode alterar SOMENTE `name` de contato vinculado e
# visível; telefone, e-mail, identifier, atributos, avatar e demais ações continuam negados (403/404)
# como em `ContactVisibility.guard!` (`app/services/connecta/scope/contact_visibility.rb`).
# O dashboard reenvia o formulário inteiro (ContactInfo.vue `updateContactField({ name })` envia só o
# nome; ContactsCard envia o formulário completo com campos inalterados), por isso o caso (g) cobre os
# campos ecoados iguais.
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta · renomear contato vinculado (Correção 01)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:contacts_path) { "/api/v1/accounts/#{account.id}/contacts" }
  let(:contact_a_path) { "#{contacts_path}/#{contact_a.id}" }
  let(:contact_control_path) { "#{contacts_path}/#{contact_control.id}" }

  let(:native_admin) { create(:user, account: account, role: :administrator) }
  let(:token_native_admin) { native_admin.create_new_auth_token }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }

  def persisted(contact, column)
    Contact.where(id: contact.id).pick(column)
  end

  it '(a) administrator nativo renomeia contato vinculado visível: 200 e nome persistido' do
    patch contact_a_path, params: { name: 'Nome Administrador' }, headers: token_native_admin, as: :json

    expect(response).to have_http_status(:ok)
    expect(persisted(contact_a, :name)).to eq('Nome Administrador')
    expect(json.dig('payload', 'name')).to eq('Nome Administrador')
  end

  it '(b) agente com grant renomeia o mesmo contato vinculado: 200 e nome persistido' do
    patch contact_a_path, params: { name: 'Nome Agente' }, headers: token_a, as: :json

    expect(response).to have_http_status(:ok)
    expect(persisted(contact_a, :name)).to eq('Nome Agente')
  end

  it '(c) alterar phone_number no contato vinculado continua 403 sem persistir' do
    before_name = persisted(contact_a, :name)
    before_phone = persisted(contact_a, :phone_number)

    patch contact_a_path, params: { phone_number: '+5511988887777' }, headers: token_a, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(persisted(contact_a, :name)).to eq(before_name)
    expect(persisted(contact_a, :phone_number)).to eq(before_phone)
  end

  it '(d) nome + telefone na mesma requisição continua 403 e nada é persistido' do
    before_name = persisted(contact_a, :name)
    before_phone = persisted(contact_a, :phone_number)

    patch contact_a_path, params: { name: 'Nome Misto', phone_number: '+5511977776666' },
                          headers: token_a, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(persisted(contact_a, :name)).to eq(before_name)
    expect(persisted(contact_a, :phone_number)).to eq(before_phone)
  end

  it '(e) contato sem vínculo em inbox marcada segue nativo (nome e telefone editáveis)' do
    patch contact_control_path, params: { name: 'Nome Livre', phone_number: '+5511966665555' },
                                headers: token_a, as: :json

    expect(response).to have_http_status(:ok)
    expect(persisted(contact_control, :name)).to eq('Nome Livre')
    expect(persisted(contact_control, :phone_number)).to eq('+5511966665555')
  end

  it '(f) contato vinculado invisível ao ator continua 404 sem persistir' do
    before_name = persisted(contact_a, :name)

    patch contact_a_path, params: { name: 'Nome Invisível' }, headers: token_b, as: :json

    expect(response).to have_http_status(:not_found)
    expect(persisted(contact_a, :name)).to eq(before_name)
  end

  it '(g) formulário do dashboard ecoando campos inalterados junto do nome: 200 e resto intacto' do
    contact_a.update!(custom_attributes: { 'rf_echo' => 'mantido' })

    patch contact_a_path,
          params: {
            name: 'Nome Ecoado',
            email: contact_a.email,
            phone_number: contact_a.phone_number,
            additional_attributes: contact_a.additional_attributes,
            custom_attributes: contact_a.custom_attributes
          },
          headers: token_a, as: :json

    expect(response).to have_http_status(:ok)
    expect(persisted(contact_a, :name)).to eq('Nome Ecoado')
    expect(persisted(contact_a, :custom_attributes)).to eq('rf_echo' => 'mantido')
    expect(persisted(contact_a, :phone_number)).to eq(contact_a.phone_number)
  end
end
