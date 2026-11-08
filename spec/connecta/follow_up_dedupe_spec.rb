require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

# Anexos de acompanhamento usam o endpoint nativo de mensagens com um nonce em
# content_attributes. O hook do fork dedupe no caminho oficial, sem fila
# fictícia nem campo novo de banco.
RSpec.describe 'Connecta · dedupe de anexos de acompanhamento', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:messages_path) { "#{conversations_path}/#{conv_a.display_id}/messages" }

  def post_follow_up(nonce, content)
    post messages_path,
         params: {
           content: content,
           content_attributes: { connecta_followup_nonce: nonce }.to_json,
           private: false
         },
         headers: agent_a.create_new_auth_token
  end

  it 'retry do mesmo nonce devolve a mensagem existente' do
    expect { post_follow_up('follow-1', 'anexo 1') }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok).or have_http_status(:created)

    expect { post_follow_up('follow-1', 'anexo 1') }.not_to change(Message, :count)
    expect(response).to have_http_status(:ok)
  end

  it 'nonces distintos criam mensagens distintas' do
    expect do
      post_follow_up('follow-a', 'anexo a')
      post_follow_up('follow-b', 'anexo b')
    end.to change(Message, :count).by(2)
  end
end
