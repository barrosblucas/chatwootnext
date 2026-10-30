require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2 parte B2 · c7b (spike G0): rotas Captain que leem conversa, exceto captain/tasks (coberto em scope_related_http_spec.rb).
# Mesmo fixture. Leitura negada em inbox marcada vira 404 sem efeito colateral (decisão 002) onde o rescue do spike está
# instalado (Copilot threads/messages create, agent_sessions show, message_reports create). Positivos autorizados e controles
# de inbox não marcada seguem nativos. Proteções de contexto/ferramentas (CopilotChatHook/CopilotToolHook) cobertas contra o
# contrato real, sem Gate stubado. RubyLLM é espião e a rede está bloqueada pelo spec_helper.
# PENDÊNCIA (outra spec, não editar aqui): inbox_update com admin nominal papel agente (401 nativo, sem allow) — ver evidência 19.
# Specs escritas em 2026-10-24 e NÃO EXECUTADAS (runs reservados à validação consolidada).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · rotas Captain que leem conversa (T0.2 parte B2, c7)', type: :request do
  include_context 'with connecta g0 scope fixture'

  let(:assistant) { create(:captain_assistant, account: account) }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_member) { member_without_grant.create_new_auth_token }

  before { allow(RubyLLM).to receive(:chat) }

  describe 'sessão de agente (captain/agent_sessions#show)' do
    let!(:captain_message) do
      create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, message_type: :outgoing, sender: assistant)
    end
    let(:agent_session) { create(:captain_agent_session, account: account, assistant: assistant, subject: conv_a, result: captain_message) }
    let(:session_path) { "/api/v1/accounts/#{account.id}/captain/agent_sessions/#{captain_message.id}" }

    before { agent_session }

    it 'agente B sem grant recebe 404 e nenhum conteúdo de A vaza' do
      get session_path, headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('CASO-A')
    end

    it 'membro da inbox sem grant recebe 404 e nenhum conteúdo de A vaza' do
      get session_path, headers: token_member

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('CASO-A')
    end

    it 'agente A com grant lê a sessão da própria conversa' do
      get session_path, headers: token_a

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'reporte de mensagem da Captain (captain/message_reports#create)' do
    let!(:captain_message) do
      create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, message_type: :outgoing, sender: assistant)
    end
    let(:report_path) { "/api/v1/accounts/#{account.id}/captain/message_reports" }
    let(:report_params) { { message_id: captain_message.id, report_reason: 'incorrect_information', description: 'Errado' } }

    before { allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true) }

    it 'agente B sem grant recebe 404 e nenhum reporte é criado' do
      expect do
        post report_path, params: report_params, headers: token_b, as: :json
      end.not_to change(Captain::MessageReport, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'membro da inbox sem grant recebe 404 e nenhum reporte é criado' do
      expect do
        post report_path, params: report_params, headers: token_member, as: :json
      end.not_to change(Captain::MessageReport, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'agente A com grant cria o reporte da mensagem de A' do
      expect do
        post report_path, params: report_params, headers: token_a, as: :json
      end.to change(Captain::MessageReport, :count).by(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'sugestões de FAQ (captain/faq_suggestions)' do
    let!(:faq_a) { assistant.faq_suggestions.create!(question: 'Pergunta do caso A', answer: 'Resposta A', source_count: 1) }
    let!(:faq_control) { assistant.faq_suggestions.create!(question: 'Pergunta do controle', answer: 'Resposta C', source_count: 1) }
    let(:faq_path) { "/api/v1/accounts/#{account.id}/captain/faq_suggestions" }

    before do
      faq_a.observations.create!(conversation: conv_a, generated_question: faq_a.question, generated_answer: faq_a.answer,
                                 language: faq_a.language)
      faq_control.observations.create!(conversation: conv_control, generated_question: faq_control.question,
                                       generated_answer: faq_control.answer, language: faq_control.language)
    end

    it 'agente B não lista sugestão gerada da conversa de A' do
      get faq_path, headers: token_b

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Pergunta do caso A')
      expect(response.parsed_body['meta']).to include('total_count' => 0)
    end

    it 'agente B recebe 404 ao abrir a sugestão de A e a pergunta não sai' do
      get "#{faq_path}/#{faq_a.id}", headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Pergunta do caso A')
    end

    it 'membro sem grant recebe 404 ao aprovar a sugestão de A e nenhuma resposta é criada' do
      expect do
        post "#{faq_path}/#{faq_a.id}/approve", headers: token_member, as: :json
      end.not_to change(Captain::AssistantResponse, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'agente A com grant abre a sugestão de A' do
      get "#{faq_path}/#{faq_a.id}", headers: token_a

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Pergunta do caso A')
    end

    it 'controle: agente A, membro da inbox de controle, vê a sugestão da conversa de controle' do
      get faq_path, headers: token_a

      expect(response.body).to include('Pergunta do controle')
    end
  end

  describe 'assistente da inbox (conversations/:id/inbox_assistant)' do
    let(:inbox_assistant_path) { "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/inbox_assistant" }

    it 'agente B recebe 404 e a conversa não é revelada' do
      get inbox_assistant_path, headers: token_b

      expect(response).to have_http_status(:not_found)
    end

    it 'membro sem grant recebe 404' do
      get inbox_assistant_path, headers: token_member

      expect(response).to have_http_status(:not_found)
    end

    it 'agente A com grant lê o assistente da inbox da própria conversa' do
      get inbox_assistant_path, headers: token_a

      expect(response).to have_http_status(:ok)
    end

    it 'controle: a conversa da inbox de controle segue nativa para A' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conv_control.display_id}/inbox_assistant", headers: token_a

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'copilot da Captain com conversation_id externo (c7b: CopilotHook barra antes de persistir/enfileirar)' do
    before { account.update!(limits: { captain_responses: 100 }) }

    let(:threads_path) { "/api/v1/accounts/#{account.id}/captain/copilot_threads" }
    let(:threads_params) { { message: 'Resuma', assistant_id: assistant.id, conversation_id: conv_a.display_id } }

    it 'agente B sem grant recebe 404 e nada é persistido nem enfileirado' do
      expect do
        expect do
          post threads_path, params: threads_params, headers: token_b, as: :json
        end.not_to change(CopilotThread, :count)
      end.not_to change(CopilotMessage, :count)

      expect(response).to have_http_status(:not_found)
      expect(Captain::Copilot::ResponseJob).not_to have_been_enqueued
      expect(RubyLLM).not_to have_received(:chat)
    end

    it 'membro da inbox sem grant recebe 404 e nada é persistido nem enfileirado' do
      expect do
        expect do
          post threads_path, params: threads_params, headers: token_member, as: :json
        end.not_to change(CopilotThread, :count)
      end.not_to change(CopilotMessage, :count)

      expect(response).to have_http_status(:not_found)
      expect(Captain::Copilot::ResponseJob).not_to have_been_enqueued
      expect(RubyLLM).not_to have_received(:chat)
    end

    it 'conversa inexistente na conta vira 404 sem revelar outra conta' do
      expect do
        post threads_path,
             params: threads_params.merge(conversation_id: 999_999_999),
             headers: token_b, as: :json
      end.not_to change(CopilotThread, :count)

      expect(response).to have_http_status(:not_found)
      expect(Captain::Copilot::ResponseJob).not_to have_been_enqueued
    end

    it 'agente A com grant cria thread com conversation_id próprio e enfileira o job' do
      expect do
        post threads_path, params: threads_params, headers: token_a, as: :json
      end.to change(CopilotThread, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(Captain::Copilot::ResponseJob).to have_been_enqueued.with(
        hash_including(conversation_id: conv_a.display_id, user_id: agent_a.id)
      )
    end

    it 'controle: agente A com conversation_id da inbox de controle segue nativo' do
      expect do
        post threads_path,
             params: threads_params.merge(conversation_id: conv_control.display_id),
             headers: token_a, as: :json
      end.to change(CopilotThread, :count).by(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'copilot_messages com conversation_id externo (c7b: CopilotHook barra antes de persistir/enfileirar)' do
    before { account.update!(limits: { captain_responses: 100 }) }

    let(:threads_path) { "/api/v1/accounts/#{account.id}/captain/copilot_threads" }
    let!(:own_thread) { create(:captain_copilot_thread, account: account, user: member_without_grant, assistant: assistant) }
    let(:messages_path) { "#{threads_path}/#{own_thread.id}/copilot_messages" }

    it 'membro sem grant recebe 404 e nada é persistido nem enfileirado' do
      expect do
        post messages_path, params: { message: 'Resuma', conversation_id: conv_a.display_id },
                            headers: token_member, as: :json
      end.not_to change(CopilotMessage, :count)

      expect(response).to have_http_status(:not_found)
      expect(Captain::Copilot::ResponseJob).not_to have_been_enqueued
      expect(RubyLLM).not_to have_received(:chat)
    end

    it 'agente B sem grant recebe 404 mesmo em thread própria' do
      own_b = create(:captain_copilot_thread, account: account, user: agent_b, assistant: assistant)

      expect do
        post "#{threads_path}/#{own_b.id}/copilot_messages",
             params: { message: 'Resuma', conversation_id: conv_a.display_id },
             headers: token_b, as: :json
      end.not_to change(CopilotMessage, :count)

      expect(response).to have_http_status(:not_found)
      expect(Captain::Copilot::ResponseJob).not_to have_been_enqueued
    end

    it 'membro sem grant cria mensagem sem conversation_id (nativo preservado)' do
      expect do
        post messages_path, params: { message: 'Resuma' }, headers: token_member, as: :json
      end.to change(CopilotMessage, :count).by(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'contexto do modelo Copilot (c7b: CopilotChatHook nega contexto alheio, sem Gate stubado)' do
    it 'alvo alheio em inbox marcada não entra no contexto (sem ID de conversa nem de contato)' do
      service = Captain::Copilot::ChatService.new(assistant, { user_id: agent_b.id, conversation_id: conv_a.display_id })

      contents = service.messages.map { |message| message[:content] }.join
      expect(contents).not_to include("Conversation ID: #{conv_a.display_id}")
      expect(contents).not_to include("Contact ID: #{contact_a.id}")
      expect(RubyLLM).not_to have_received(:chat)
    end

    it 'membro sem grant não recebe contexto da conversa de A' do
      service = Captain::Copilot::ChatService.new(assistant, { user_id: member_without_grant.id,
                                                               conversation_id: conv_a.display_id })

      contents = service.messages.map { |message| message[:content] }.join
      expect(contents).not_to include("Conversation ID: #{conv_a.display_id}")
      expect(contents).not_to include("Contact ID: #{contact_a.id}")
    end

    it 'usuário autorizado recebe o contexto permitido da própria conversa' do
      service = Captain::Copilot::ChatService.new(assistant, { user_id: agent_a.id, conversation_id: conv_a.display_id })

      contents = service.messages.map { |message| message[:content] }.join
      expect(contents).to include("Conversation ID: #{conv_a.display_id}")
    end

    it 'controle: conversa de inbox não marcada segue nativa para A' do
      service = Captain::Copilot::ChatService.new(assistant, { user_id: agent_a.id, conversation_id: conv_control.display_id })

      contents = service.messages.map { |message| message[:content] }.join
      expect(contents).to include("Conversation ID: #{conv_control.display_id}")
    end
  end

  describe 'SearchContacts filtra cada resultado antes de formatar (RF1, sem Gate stubado)' do
    it 'busca ampla/sem filtros de A so formata o contato permitido e o unmarked ' \
       '(sem ID/nome/telefone/content de B)' do
      b_probe = create(:contact, account: account, name: 'RF1 Probe B', email: 'rf1-probe-b@example.com')
      unmarked_probe = create(:contact, account: account, name: 'RF1 Probe Livre')

      result = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_a).execute

      expect(result).not_to include("Contact ID: ##{contact_b.id}")
      expect(result).not_to include(contact_b.name)
      expect(result).not_to include(contact_b.phone_number) if contact_b.phone_number.present?
      # Contato sem vínculo com inbox marcada é nativo e visível (evidência 36-rf1-search §22-28).
      expect(result).to include("Contact ID: ##{b_probe.id}")
      expect(result).to include("Contact ID: ##{contact_a.id}")
      expect(result).to include("Contact ID: ##{unmarked_probe.id}")
    end

    it 'nome compartilhado "Maria" entrega a A so o seu contato e o unmarked (B e membro sem grant: negativos)' do # rubocop:disable RSpec/MultipleExpectations
      contact_a.update!(name: 'Maria Compartilhada A')
      contact_b.update!(name: 'Maria Compartilhada B')
      contact_orphan.update!(name: 'Maria Compartilhada Livre')

      result_a = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_a)
                                                               .execute(name: 'Maria Compartilhada')
      result_b = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_b)
                                                               .execute(name: 'Maria Compartilhada')
      result_member = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: member_without_grant)
                                                                    .execute(name: 'Maria Compartilhada')

      # contact_orphan tem vínculo com inbox marcada: só aparece a quem vê a conversa dele (evidência 36-rf1-search §22-28).
      expect(result_a).to include("Contact ID: ##{contact_a.id}")
      expect(result_a).not_to include("Contact ID: ##{contact_orphan.id}")
      expect(result_a).not_to include("Contact ID: ##{contact_b.id}")
      expect(result_a).not_to include('Maria Compartilhada B')

      expect(result_b).to include("Contact ID: ##{contact_b.id}")
      expect(result_b).not_to include("Contact ID: ##{contact_orphan.id}")
      expect(result_b).not_to include("Contact ID: ##{contact_a.id}")
      expect(result_b).not_to include('Maria Compartilhada A')

      expect(result_member).not_to include("Contact ID: ##{contact_orphan.id}")
      expect(result_member).not_to include("Contact ID: ##{contact_a.id}")
      expect(result_member).not_to include("Contact ID: ##{contact_b.id}")
    end

    it 'busca com filtro nativo preservado continua negando alvo alheio e mantendo positivo autorizado' do
      # Fila de round-robin no Redis não é o objeto deste spec (precedente: runtime_reception_scope_spec.rb:26-28).
      allow(Redis::Alfred).to receive(:lpush)
      allow(Redis::Alfred).to receive(:lrem)
      allow(Redis::Alfred).to receive(:delete)
      known_b = create(:contact, account: account, name: 'RF1 Positivo B', email: 'rf1-positivo-b@example.com')
      create(:conversation, account: account, inbox: whatsapp_inbox, contact: known_b)
      Connecta::Scope::ConversationScope.create!(
        conversation_id: known_b.conversations.last.id, inbox_id: whatsapp_inbox.id, contact_id: known_b.id,
        org_unit: org_b, state: 'active', case_protocol: 'RF1-PB', case_version: 1
      )
      denied = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_a)
                                                             .execute(email: 'rf1-positivo-b@example.com')
      allowed = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_b)
                                                              .execute(email: 'rf1-positivo-b@example.com')

      expect(denied).to eq('No contacts found')
      expect(denied).not_to include("Contact ID: ##{known_b.id}")
      expect(allowed).to include("Contact ID: ##{known_b.id}")
    end
  end

  describe 'ferramentas Copilot (c7b: CopilotToolHook nega alvo alheio, sem Gate stubado)' do
    it 'GetConversation com alvo alheio devolve não encontrado sem conteúdo' do
      result = Captain::Tools::Copilot::GetConversationService.new(assistant, user: agent_b)
                                                              .execute(conversation_id: conv_a.display_id)

      expect(result).to eq('Conversation not found')
    end

    it 'GetConversation autorizado devolve o conteúdo permitido' do
      result = Captain::Tools::Copilot::GetConversationService.new(assistant, user: agent_a)
                                                              .execute(conversation_id: conv_a.display_id)

      expect(result).to include("Conversation ID: ##{conv_a.display_id}")
    end

    it 'GetContact com alvo alheio devolve não encontrado sem conteúdo' do
      result = Captain::Tools::Copilot::GetContactService.new(assistant, user: agent_b)
                                                         .execute(contact_id: contact_a.id)

      expect(result).to eq('Contact not found')
    end

    it 'GetContact autorizado devolve o conteúdo permitido' do
      result = Captain::Tools::Copilot::GetContactService.new(assistant, user: agent_a)
                                                         .execute(contact_id: contact_a.id)

      expect(result).to include("Contact ID: ##{contact_a.id}")
    end

    it 'SearchContacts por nome do contato de A não expõe contato alheio a B' do
      result = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_b)
                                                             .execute(name: contact_a.name)

      expect(result).not_to include("Contact ID: ##{contact_a.id}")
    end

    it 'SearchContacts autorizado encontra o contato permitido' do
      result = Captain::Tools::Copilot::SearchContactsService.new(assistant, user: agent_a)
                                                             .execute(name: contact_a.name)

      expect(result).to include("Contact ID: ##{contact_a.id}")
    end
  end
end
