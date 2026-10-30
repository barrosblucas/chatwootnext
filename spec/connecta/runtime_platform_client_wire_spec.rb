require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

# Prova de fio HMAC v1 com request-target REAL (loopback TCP sintetico).
# Motivacao: o spec F2 usa WebMock/HTTParty, que pode reordenar a query
# alfabeticamente; este spec prova que o header X-Connecta-Signature v1
# cobre o request-target EXATO recebido no fio (incluindo ordem nao
# alfabetica e actor_authority), sem WebMock como unica prova.
# Sem rede externa: servidor TCP loopback por teste, com ensure/restore.
# Sem credenciais reais: segredo sintetico de fixture.
RSpec.describe 'Connecta runtime · HMAC cobre request-target real do fio (v1)' do # rubocop:disable RSpec/DescribeClass
  let(:wire_secret) { 'wire-synthetic-hmac-secret' }

  def read_loopback_request(socket)
    request_line = socket.gets
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      key, value = line.chomp.split(': ', 2)
      headers[key] = value
    end
    content_length = headers['Content-Length'].to_i
    body = content_length.positive? ? socket.read(content_length) : ''
    { request_line: request_line, headers: headers, body: body.to_s }
  end

  def with_loopback_server
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    received = Queue.new
    thread = Thread.new do
      socket = server.accept
      begin
        received << read_loopback_request(socket)
        payload = '{"ok":true}'
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{payload.bytesize}\r\n" \
                     "Connection: close\r\n\r\n#{payload}")
      ensure
        socket.close
      end
    end
    yield port, received
  ensure
    thread&.join(5)
    server&.close
  end

  def signature_valid?(headers, request_target, body)
    signature = headers['X-Connecta-Signature'].to_s
    timestamp = headers['X-Connecta-Timestamp'].to_s
    canonical = [timestamp, 'GET', request_target, body].join('.')
    signature == "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', wire_secret, canonical)}"
  end

  it 'GET com query fora de ordem alfabetica: assinatura cobre o target exato do fio' do
    with_loopback_server do |port, received|
      targeted = Connecta::Runtime::PlatformClient.new(base_url: "http://127.0.0.1:#{port}", secret: wire_secret)
      # Ordem deliberadamente NAO alfabetica: actor_authority primeiro, para provar
      # que o normalizador nao mascara a ordem real do fio.
      raw_query = 'actor_authority=chatwoot_account_admin&conversation_id=9&account_id=3&actor_chatwoot_user_id=7'
      targeted.get("/attendance/v1/transfer-destinations?#{raw_query}")

      captured = received.pop
      request_target = captured[:request_line].split[1]
      # O fio carrega a query na ordem enviada (nao alfabetica)...
      expect(request_target).to eq("/attendance/v1/transfer-destinations?#{raw_query}")
      # ...e o header v1 cobre EXATAMENTE esse target canonico com o claim.
      expect(request_target).to include('actor_authority=chatwoot_account_admin')
      expect(signature_valid?(captured[:headers], request_target, '')).to be(true)
    end
  end
end
