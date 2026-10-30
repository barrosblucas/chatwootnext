require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

# T0.4 (EVID4): caracterização do acesso atual a anexos de canal Baileys. Não implementa ACL: registra o que o app
# entrega hoje a quem possui o link. Fixtures sintéticas; storage :test (Disk) em tmp/storage do repo, blobs apagados no after.
# Medição por requisição HTTP sem sessão. A URL que a gem gera não é prova do serviço privado: o TTL é medido.
RSpec.describe 'Attachment access on Baileys channels (T0.4 · EVID4)', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:account) { create(:account) }
  # Sem HTTP: validação de credenciais e sincronização de templates são os únicos pontos que chamariam o servidor Baileys.
  let!(:channel) { create(:channel_whatsapp, account: account, provider: 'baileys', sync_templates: false, validate_provider_config: false) }
  let!(:inbox) { create(:inbox, channel: channel, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:body) { 'conteudo-sintetico-g0' }
  let!(:attachment) do
    Attachment.new(account: account, message: message, file_type: :file).tap do |record|
      record.file.attach(io: StringIO.new(body), filename: 'canario.txt', content_type: 'text/plain')
      record.save!
    end
  end
  let(:blob) { attachment.file.blob }
  let(:proxy_path) { Rails.application.routes.url_helpers.rails_storage_proxy_path(blob, only_path: true) }
  let(:base_time) { Time.current }

  after do
    blob.service.delete(blob.key) if attachment.file.attached?
  end

  describe 'what the model returns' do
    it 'the test environment stores blobs in the private Disk service, not in a public or S3 service' do
      expect(blob.service).to be_a(ActiveStorage::Service::DiskService)
    end

    it 'file_url is the blob redirect link signed by the blob signed_id' do
      expect(attachment.file_url).to end_with("/rails/active_storage/blobs/redirect/#{blob.signed_id}/canario.txt")
    end

    it 'download_url is the Disk service URL with the signed key in the path' do
      expect(attachment.download_url).to match(%r{/rails/active_storage/disk/[^/]+/canario\.txt\z})
    end

    it 'blob signed_id is identical before and after advancing the clock (no expiry)' do
      before_travel = blob.signed_id
      travel_to(base_time + 1.year) { expect(blob.signed_id).to eq(before_travel) }
    end

    it 'file_url does not change when the clock advances, but download_url issues a new token' do
      link = attachment.file_url
      disk_url = attachment.download_url
      travel_to(base_time + 10.minutes) do
        expect(attachment.file_url).to eq(link)
        expect(attachment.download_url).not_to eq(disk_url)
      end
    end
  end

  describe 'expiry measured by HTTP request (no session, no user token)' do
    it 'Disk URL answers 200 within 5 minutes and 404 afterwards' do
      disk_url = travel_to(base_time) { attachment.download_url }
      travel_to(base_time + 4.minutes + 50.seconds) do
        get disk_url
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(body)
      end
      travel_to(base_time + 5.minutes + 10.seconds) do
        get disk_url
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'blob redirect link does not expire: after 1 year it redirects to a fresh Disk URL and serves the content' do
      link = attachment.file_url
      travel_to(base_time + 1.year) do
        get link
        expect(response).to have_http_status(:found)
        expect(response.location).to include('/rails/active_storage/disk/')
        get response.location
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(body)
      end
    end

    it 'blob proxy link does not expire: after 1 year it serves the content without redirecting' do
      travel_to(base_time + 1.year) do
        get proxy_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(body)
      end
    end

    it 'tampered signatures get 404 on redirect, proxy and Disk routes' do
      tampered = "#{blob.signed_id}x"
      get "/rails/active_storage/blobs/redirect/#{tampered}/canario.txt"
      expect(response).to have_http_status(:not_found)
      get "/rails/active_storage/blobs/proxy/#{tampered}/canario.txt"
      expect(response).to have_http_status(:not_found)
      get '/rails/active_storage/disk/tokenadulterado/canario.txt'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'authentication on ActiveStorage routes' do
    # Caracterização: fixa os callbacks atuais. Cada um é listado com o efeito observado no código da gem/app.
    # Audited::Sweeper registra o usuário para auditoria; Proc (set_current) define url_options do ActiveStorage;
    # set_blob/set_representation resolvem o signed_id; authenticate_secure_password! (devise-secure_password) só
    # redireciona com flag de senha expirada na sessão; verify_* são checagens de CSRF/origem, sem exigir usuário.
    it 'exact list of before_action callbacks on ActiveStorage controllers (no user or account check)' do
      controllers = [
        ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
        ActiveStorage::DiskController, ActiveStorage::Representations::RedirectController
      ]
      filters = controllers.flat_map do |controller|
        controller._process_action_callbacks.map { |callback| callback.filter.is_a?(Symbol) ? callback.filter.to_s : callback.filter.class.name }
      end
      expect(filters.uniq).to match_array(
        %w[Audited::Sweeper Proc authenticate_secure_password! set_blob set_representation
           verify_authenticity_token verify_same_origin_request]
      )
    end
  end

  describe 'thumb_url for images' do
    let!(:image) do
      Attachment.new(account: account, message: message, file_type: :image).tap do |record|
        record.file.attach(io: StringIO.new('png-sintetico'), filename: 'miniatura.png', content_type: 'image/png')
        record.save!
      end
    end

    after { image.file.blob.service.delete(image.file.blob.key) if image.file.attached? }

    it 'thumb_url is a representation route with the blob signed_id and no expiry' do
      thumb = image.thumb_url
      expect(thumb).to include('/rails/active_storage/representations/redirect/')
      expect(thumb).to include(image.file.blob.signed_id)
      travel_to(base_time + 1.year) { expect(ActiveStorage::Blob.find_signed(image.file.blob.signed_id)).to eq(image.file.blob) }
    end

    it 'representation with a tampered signature returns 404 without processing the image' do
      get "/rails/active_storage/representations/redirect/#{image.file.blob.signed_id}x/variante/miniatura.png"
      expect(response).to have_http_status(:not_found)
    end
  end
end
