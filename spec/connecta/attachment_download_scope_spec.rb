require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'
require_relative 'support/g0_scope_schema'
require_relative 'support/g0_scope_fixture'

# T0.2-c3 (spike G0): downloads de anexo de conversa marcada contra os hooks reais.
# Contrato sob teste (somente leitura de código nesta frente; execução pendente):
# - `AttachmentToken.issue/read` assina por 5 min com attachment_id/blob_id/user_id/account_id/epoch.
# - `AttachmentUrlHook#file_url/#thumb_url/#download_url (+ #inline_audio_url privado)` aponta à rota
#   autorizada do Installer quando há Current.user + conversa em inbox marcada; senão segue nativo.
# - `AttachmentDownloadsController#show` exige Gate de leitura (`attachment_download`) e serve bytes inline,
#   sem redirect para URL global de blob.
# - `ActiveStorageGuard` nega redirect/proxy/representations de blob vinculado a inbox marcada.
# Positivos e negativos usam usuário + conta + epoch + expiração + Gate reais via HTTP; nenhum Gate é stubado.
# Storage Disk local de teste; nenhuma URL externa é chamada. Stub de transporte externo é desnecessário aqui.
# Specs escritas em 2026-10-24 e NÃO EXECUTADAS (runs reservados à validação consolidada).
Connecta::G0ScopeSchema.ensure!
Connecta::Scope::Installer.install!

RSpec.describe 'Connecta G0 · download de anexo marcado (T0.2-c3)', type: :request do
  include_context 'with connecta g0 scope fixture'
  include ActiveSupport::Testing::TimeHelpers

  before do
    stub_const('BODY', 'bytes-sinteticos-g0-t02-c3')
    stub_const('IMAGE_PATH', Rails.root.join('spec/assets/avatar.png'))
    create(:inbox_member, inbox: whatsapp_inbox, user: native_admin)
    Connecta::Scope::UserAuthEpoch.create!(user_id: native_admin.id, epoch: 1)
  end

  let(:token_a) { agent_a.create_new_auth_token }
  let(:token_b) { agent_b.create_new_auth_token }
  let(:token_member) { member_without_grant.create_new_auth_token }
  let(:token_admin) { admin_nominal.create_new_auth_token }
  let!(:native_admin) { create(:user, account: account, role: :administrator) }
  let(:token_native) { native_admin.create_new_auth_token }

  let!(:message_a) do
    create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_a, sender: agent_a,
                     message_type: :outgoing, content: 'mensagem com anexo de A')
  end
  let!(:attachment) do
    Attachment.new(account: account, message: message_a, file_type: :file).tap do |record|
      record.file.attach(io: StringIO.new(BODY), filename: 'canario.txt', content_type: 'text/plain')
      record.save!
    end
  end
  let(:blob) { attachment.file.blob }
  let(:download_path) { "/api/v1/accounts/#{account.id}/connecta_attachments/#{attachment.id}/download" }
  let(:messages_path) { "/api/v1/accounts/#{account.id}/conversations/#{conv_a.display_id}/messages" }

  # Emite o token exatamente como o hook faria para o usuário autenticado na sessão de teste,
  # com a epoch viva no banco (leitura real de `Connecta::Scope::UserAuthEpoch`).
  def issue_token_for(user, attachment_record = attachment)
    epoch = Connecta::Scope::UserAuthEpoch.find_by!(user_id: user.id).epoch
    Current.user = user
    Connecta::Scope::AttachmentToken.issue(attachment: attachment_record, user: user, account: account, epoch: epoch)
  ensure
    Current.reset
  end

  def download_url_for(user, extra_params = {})
    token = issue_token_for(user)
    "#{download_path}?token=#{CGI.escape(token)}#{extra_params.map { |key, value| "&#{key}=#{value}" }.join}"
  end

  def epoch_row_for(user)
    Connecta::Scope::UserAuthEpoch.find_by!(user_id: user.id)
  end

  after do
    attachment.file.blob.service.delete(attachment.file.blob.key) if attachment.file.attached?
    Current.reset
  end

  describe 'autorizado recebe bytes; Gate nega sem grant' do
    it 'agente A com grant recebe os bytes inline com o content-type do blob' do
      get download_url_for(agent_a), headers: token_a

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(BODY)
      expect(response.headers['Content-Disposition']).to include('inline')
    end

    it 'token de A com sessão de B é negado com 404 e nada do conteúdo vaza' do
      token = issue_token_for(agent_a)

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'agente B (outro setor) com token próprio recebe 404 do Gate e nada do conteúdo vaza' do
      get download_url_for(agent_b), headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'membro da inbox sem grant recebe 404 do Gate e nada do conteúdo vaza' do
      get download_url_for(member_without_grant), headers: token_member

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    # Contrato real (nativo, sem Gate stubado): DeviseTokenAuth responde 401 direto quando não há
    # credencial válida — não é o Gate que nega. Sem sessão o controller nunca chega ao Gate/download.
    it 'sem autenticação a rota nativa responde 401 antes do download' do
      get download_url_for(agent_a)

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include(BODY)
    end

    # Plano §5.3/§5.6/Q10: admin nominal lê tudo com auditoria; socket só carrega metadados e o
    # conteúdo vem ao abrir (auditado). Token próprio/user/account/epoch/expiração preservados —
    # admin com token de outro usuário continua negado (vínculo, sem consultar o Gate).
    # I.1b: admin NATIVO same-account recebe 200 auditado sem grant setorial (Gate real,
    # token próprio/user/account/epoch/expiração preservados).
    it 'admin nativo com token próprio recebe 200 auditado no download (Gate real, sem stub)' do
      expect do
        get download_url_for(native_admin), headers: token_native
      end.to change {
        Connecta::Scope::AccessAudit.where(user_id: native_admin.id, conversation_id: conv_a.id,
                                           surface: 'conversation', access_path: 'attachment_download',
                                           decision: 'allow').count
      }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(BODY)
    end

    # I.1b negativa cross-user: nativo com token de outro usuário continua negado no vínculo.
    it 'admin nativo com token de outro usuário é negado e auditado (vínculo, sem Gate)' do
      token = issue_token_for(agent_a)

      expect do
        get "#{download_path}?token=#{CGI.escape(token)}", headers: token_native
      end.to change {
        Connecta::Scope::AccessAudit.where(user_id: native_admin.id, conversation_id: conv_a.id,
                                           surface: 'attachment', access_path: 'attachment_download',
                                           decision: 'deny').count
      }.by(1)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    # I.1b: upload direto cria blob para nativo same-account (hook real, sem stub de Gate).
    it 'admin nativo cria blob via upload direto na conversa de outro setor' do
      expect do
        post "/api/v1/accounts/#{account.id}/conversations/#{conv_b.display_id}/direct_uploads",
             params: { blob: { filename: 'a.png', byte_size: '1234', checksum: 'dGVzdA==', content_type: 'image/png' } },
             headers: token_native, as: :json
      end.to change(ActiveStorage::Blob, :count).by(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'vínculo token × usuário/conta/anexo/blob' do
    # Contrato実: Gate audita allow/deny em 'conversation' (Gate#decide), NÃO em 'attachment'. Quando o
    # vínculo do token falha, o controller audita deny em 'attachment/attachment_download' (AC1, sem
    # tocar no Gate). O exemplo abaixo cobre exatamente esse caminho (token válido porém de outro
    # usuário: Gate nunca é consultado porque o vínculo já negou antes).
    it 'token de outro usuário é negado e auditado com decision deny' do
      token = issue_token_for(agent_a)

      expect do
        get "#{download_path}?token=#{CGI.escape(token)}", headers: token_b
      end.to change {
        Connecta::Scope::AccessAudit.where(user_id: agent_b.id, conversation_id: conv_a.id,
                                           surface: 'attachment', access_path: 'attachment_download',
                                           decision: 'deny').count
      }.by(1)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'token com account_id de outra conta é negado mesmo com usuário e epoch válidos' do
      other_account = create(:account)
      epoch = epoch_row_for(agent_a).epoch
      token = Rails.application.message_verifier('ActiveStorage').generate(
        { 'attachment_id' => attachment.id, 'blob_id' => blob.id, 'user_id' => agent_a.id,
          'account_id' => other_account.id, 'epoch' => epoch },
        purpose: Connecta::Scope::AttachmentToken::PURPOSE, expires_in: Connecta::Scope::AttachmentToken::TTL
      )

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'token com anexo de outra conversa marcada é negado no vínculo attachment_id' do
      message_b = create(:message, account: account, inbox: whatsapp_inbox, conversation: conv_b, sender: agent_b,
                                   message_type: :outgoing, content: 'mensagem com anexo de B')
      other = Attachment.new(account: account, message: message_b, file_type: :file).tap do |record|
        record.file.attach(io: StringIO.new('outro-bytes'), filename: 'outro.txt', content_type: 'text/plain')
        record.save!
      end
      token_for_other = issue_token_for(agent_b, other)

      get "#{download_path}?token=#{CGI.escape(token_for_other)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    ensure
      other&.file&.blob&.service&.delete(other.file.blob.key) if other&.file&.attached?
    end

    it 'blob trocado após a emissão invalida o token mesmo com os demais vínculos iguais' do
      token = issue_token_for(agent_a)
      blob_id_before = blob.id
      attachment.file.blob.service.delete(blob.key)
      attachment.file.attach(io: StringIO.new('bytes-novos'), filename: 'canario.txt', content_type: 'text/plain')

      expect(attachment.file.blob.id).not_to eq(blob_id_before)

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'token adulterado (assinatura quebrada) é negado com 404' do
      token = "#{issue_token_for(agent_a)}x"

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'token ausente é negado com 404' do
      get download_path, headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end
  end

  describe 'expiração e epoch' do
    # O TTL vive no envelope assinado (`AttachmentToken::TTL`, 5 min): o próprio verifier rejeita o
    # token expirado e o controller cai no `Denied, :not_found` (404, sem vazar bytes). O Agosto
    # da conta e o heartbeat são mantidos frescos; só o relógio avança.
    it 'token expirado há 6 minutos é negado, mas o mesmo token vale dentro dos 5 minutos' do
      fresh_token = issue_token_for(agent_a)
      travel_to(4.minutes.from_now) do
        projection_heartbeat.update!(last_heartbeat_at: Time.current)
        get "#{download_path}?token=#{CGI.escape(fresh_token)}", headers: token_a

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(BODY)
      end

      travel_to(6.minutes.from_now) do
        projection_heartbeat.update!(last_heartbeat_at: Time.current)
        get "#{download_path}?token=#{CGI.escape(fresh_token)}", headers: token_a

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(BODY)
      end
    end

    it 'epoch alterada após a emissão invalida o token ainda válido' do
      token = issue_token_for(agent_a)
      epoch_row_for(agent_a).update!(epoch: epoch_row_for(agent_a).epoch + 1)

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'revogação local tira o acesso mesmo com token ainda válido' do
      token = issue_token_for(agent_a)
      epoch_row_for(agent_a).update!(revoked_locally_at: Time.current)

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'epoch removida do banco nega o download (fail-closed), mesmo com token assinado' do
      token = issue_token_for(agent_a)
      epoch_row_for(agent_a).destroy!

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end
  end

  describe 'transferência e revogação de grant tiram o acesso com token válido' do
    # Estado `transferred_out` sai de `READ_STATES`: o Gate real nega a leitura (404) sem stub,
    # embora o token continue assinado e não expirado.
    it 'conversa com state transferred_out nega o download com token ainda válido' do
      token = issue_token_for(agent_a)
      Connecta::Scope::ConversationScope.find_by!(conversation_id: conv_a.id).update!(state: 'transferred_out')

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'grant revogado nega o download com token ainda válido' do
      token = issue_token_for(agent_a)
      Connecta::Scope::UserGrant.where(user_id: agent_a.id).destroy_all

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'heartbeat vencido nega o download com token ainda válido (Gate real, sem stub)' do
      token = issue_token_for(agent_a)
      projection_heartbeat.update!(last_heartbeat_at: 10.minutes.ago)

      get "#{download_path}?token=#{CGI.escape(token)}", headers: token_a

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end
  end

  describe 'serialização marcada usa a rota autorizada; sem Current.user segue nativo' do
    # `push_event_data` é o que as views `_message`/`_attachment` serializam; `data_url` vem de
    # `file_url` e carrega a rota autorizada quando há Current.user + inbox marcada.
    it 'mensagem serializada com Current.user carrega file_url/thumb_url/download_url/inline_audio na rota autorizada' do
      Current.user = agent_a
      data = attachment.push_event_data

      expect(data[:data_url]).to include("/api/v1/accounts/#{account.id}/connecta_attachments/#{attachment.id}/download")
      expect(data[:data_url]).to include('token=')
      expect(attachment.download_url).to include(
        "/api/v1/accounts/#{account.id}/connecta_attachments/#{attachment.id}/download"
      )
    ensure
      Current.reset
    end

    it 'thumb de imagem marcada vai à rota autorizada com o parâmetro thumb' do
      image_attachment = Attachment.new(account: account, message: message_a, file_type: :image).tap do |record|
        record.file.attach(io: IMAGE_PATH.open, filename: 'avatar.png', content_type: 'image/png')
        record.save!
      end
      Current.user = agent_a

      expect(image_attachment.thumb_url).to include(
        "/api/v1/accounts/#{account.id}/connecta_attachments/#{image_attachment.id}/download"
      )
      expect(image_attachment.thumb_url).to include('thumb=1')
    ensure
      Current.reset
      image_attachment.file.blob.service.delete(image_attachment.file.blob.key) if image_attachment.file.attached?
    end

    it 'áudio marcado serializa inline_audio_url na rota autorizada quando autenticado' do
      audio = Attachment.new(account: account, message: message_a, file_type: :audio).tap do |record|
        record.file.attach(io: StringIO.new('audio-sintetico'), filename: 'nota.ogg', content_type: 'audio/ogg')
        record.save!
      end
      Current.user = agent_a

      expect(audio.push_event_data[:data_url]).to include(
        "/api/v1/accounts/#{account.id}/connecta_attachments/#{audio.id}/download"
      )
    ensure
      Current.reset
      audio.file.blob.service.delete(audio.file.blob.key) if audio.file.attached?
    end

    it 'anexo de inbox não marcada preserva o comportamento nativo (controle)' do
      control_message = create(:message, account: account, inbox: control_inbox, conversation: conv_control,
                                         sender: agent_a, message_type: :outgoing, content: 'mensagem do controle')
      control_attachment = Attachment.new(account: account, message: control_message, file_type: :file).tap do |record|
        record.file.attach(io: StringIO.new('controle'), filename: 'controle.txt', content_type: 'text/plain')
        record.save!
      end
      Current.user = agent_a

      expect(control_attachment.file_url).to include('/rails/active_storage/blobs/redirect/')
      expect(control_attachment.file_url).not_to include('connecta_attachments')
    ensure
      Current.reset
      control_attachment.file.blob.service.delete(control_attachment.file.blob.key) if control_attachment.file.attached?
    end
  end

  describe 'links legados não contornam o acesso marcado' do
    # O guard do spike nega (404) redirect/proxy de blobs e redirect/proxy de representations quando
    # o blob está vinculado a anexo de conversa marcada; a checagem lê o vínculo vivo no banco, então
    # vale inclusive para URL emitida antes da proteção. Disk direto segue nativo (limite documentado).
    it 'redirect legado do blob marcado responde 404 e não serve os bytes' do
      legacy = attachment.file_url

      get legacy

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'proxy legado do blob marcado responde 404 e não serve os bytes' do
      proxy = Rails.application.routes.url_helpers.rails_storage_proxy_path(blob, only_path: true)

      get proxy

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(BODY)
    end

    it 'representation legada do thumb marcado responde 404' do
      image_attachment = Attachment.new(account: account, message: message_a, file_type: :image).tap do |record|
        record.file.attach(io: IMAGE_PATH.open, filename: 'avatar.png', content_type: 'image/png')
        record.save!
      end
      legacy_thumb = image_attachment.thumb_url

      get legacy_thumb

      expect(response).to have_http_status(:not_found)
    ensure
      image_attachment.file.blob.service.delete(image_attachment.file.blob.key) if image_attachment.file.attached?
    end

    it 'anexo do controle nativo segue servindo pelo proxy legado (sem vínculo marcado)' do
      control_message = create(:message, account: account, inbox: control_inbox, conversation: conv_control,
                                         sender: agent_a, message_type: :outgoing, content: 'controle proxy')
      control_attachment = Attachment.new(account: account, message: control_message, file_type: :file).tap do |record|
        record.file.attach(io: StringIO.new('controle'), filename: 'controle.txt', content_type: 'text/plain')
        record.save!
      end
      control_proxy = Rails.application.routes.url_helpers.rails_storage_proxy_path(control_attachment.file.blob,
                                                                                    only_path: true)

      get control_proxy

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('controle')
    ensure
      control_attachment.file.blob.service.delete(control_attachment.file.blob.key) if control_attachment.file.attached?
    end
  end
end
