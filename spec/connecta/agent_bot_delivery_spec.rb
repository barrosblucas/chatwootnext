require_relative '../support/connecta/g0_target_guard'
Connecta::G0TargetGuard.verify!
require 'rails_helper'

# T0.5 (EVID6): entrega de eventos ao AgentBot, do listener até a requisição HTTP.
# Listener, jobs e Trigger são os reais. SafeFetch é o único ponto stubado (nenhuma rede).
# Retentativas de 429/500 (wait 3s) são avançadas com perform_enqueued_jobs(at:) em passos com folga (base, +4s, +8s),
# porque o ActiveJob agenda a retentativa a partir do relógio de execução. Demais falhas (404/timeout) usam o retry_on
# genérico do WebhookJob (5 tentativas, backoff polinomial) e só escalam quando esgotadas. Não há garantia de ordem
# global de entregas.
RSpec.describe 'AgentBot delivery (T0.5 · EVID6)', type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:base_time) { Time.zone.now.change(usec: 0) }
  let(:assignee_url) { 'https://bot-assignee.example.test/hook' }
  let(:inbox_url) { 'https://bot-inbox.example.test/hook' }
  let(:assignee_for_conversation) { assignee_bot }
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:assignee_bot) { create(:agent_bot, outgoing_url: assignee_url, secret: 'segredo-sintetico-a') }
  let!(:inbox_bot) { create(:agent_bot, outgoing_url: inbox_url, secret: 'segredo-sintetico-b') }
  # Ordem importa: com bot ativo na caixa, a criação da conversa atribui o bot da caixa como assignee (before_create).
  # Por isso o assignee é definido depois da criação e o agent_bot_inbox só existe a partir daí.
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, status: :pending).tap do |record|
      record.update!(assignee_agent_bot: assignee_for_conversation)
    end
  end
  let!(:message) { create(:message, message_type: 'incoming', account: account, inbox: inbox, conversation: conversation) }
  let(:event) { Events::Base.new('message.created', base_time, message: message) }
  let(:listener) { AgentBotListener.instance }

  # Roteiro por URL: cada chamada consome o próximo erro; sem erro, a entrega é 2xx. Sem rede.
  let(:scripted) { {} }
  let(:deliveries) { [] }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: inbox_bot)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
    allow(SafeFetch).to receive(:fetch) do |url, **options|
      error = (scripted[url] ||= []).shift
      deliveries << { url: url, outcome: error ? error.message : '2xx', body: options[:body], headers: options[:headers],
                      open_timeout: options[:open_timeout], read_timeout: options[:read_timeout] }
      raise error if error
    end
  end

  describe 'bot selection (enqueue order, not delivery order)' do
    it 'enqueues assignee before the inbox bot, one job per bot' do
      travel_to(base_time) { listener.message_created(event) }
      queued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == AgentBots::WebhookJob }
      expect(queued.map { |job| job[:args].first }).to eq([assignee_url, inbox_url])
    end

    context 'when the same bot is the assignee and the inbox bot' do
      let(:assignee_for_conversation) { inbox_bot }

      it 'does not duplicate the delivery' do
        travel_to(base_time) { listener.message_created(event) }
        queued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == AgentBots::WebhookJob }
        expect(queued.map { |job| job[:args].first }).to eq([inbox_url])
      end
    end

    context 'when the first bot answers 429 on the first attempt' do
      let(:scripted) { { assignee_url => [SafeFetch::HttpError.new('429 Too Many Requests')] } }

      it 'completion order inverts the selection: the inbox bot completes before the assignee retry' do
        travel_to(base_time) { listener.message_created(event) }
        travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
        travel_to(base_time + 4.seconds) { perform_enqueued_jobs(at: base_time + 4.seconds) }
        completed = deliveries.select { |delivery| delivery[:outcome] == '2xx' }.map { |delivery| delivery[:url] }
        expect(completed).to eq([inbox_url, assignee_url])
      end
    end
  end

  describe 'request and signature' do
    it 'sends JSON with HMAC-SHA256 over the exact "timestamp.body" and a UUID delivery_id' do
      travel_to(base_time) do
        listener.message_created(event)
        perform_enqueued_jobs(at: base_time)
      end
      delivery = deliveries.find { |entry| entry[:url] == assignee_url }
      timestamp = delivery[:headers]['X-Chatwoot-Timestamp']
      expected = OpenSSL::HMAC.hexdigest('SHA256', 'segredo-sintetico-a', "#{timestamp}.#{delivery[:body]}")

      expect(timestamp).to eq(base_time.to_i.to_s)
      expect(delivery[:headers]['X-Chatwoot-Signature']).to eq("sha256=#{expected}")
      expect(JSON.parse(delivery[:body])).to include('event' => 'message_created', 'id' => message.id)
      expect(delivery[:headers]['X-Chatwoot-Delivery']).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(delivery[:headers]).to include('Content-Type' => 'application/json')
    end

    it 'gives each bot its own delivery_id for the same event' do
      travel_to(base_time) do
        listener.message_created(event)
        perform_enqueued_jobs(at: base_time)
      end
      expect(deliveries.map { |delivery| delivery[:headers]['X-Chatwoot-Delivery'] }.uniq.size).to eq(2)
    end

    it 'uses the 5-second default timeout when WEBHOOK_TIMEOUT is empty' do
      allow(GlobalConfig).to receive(:get_value).and_call_original
      allow(GlobalConfig).to receive(:get_value).with('WEBHOOK_TIMEOUT').and_return(nil)
      travel_to(base_time) do
        listener.message_created(event)
        perform_enqueued_jobs(at: base_time)
      end
      expect(deliveries.first.values_at(:open_timeout, :read_timeout)).to eq([5, 5])
    end

    it 'uses WEBHOOK_TIMEOUT when it is configured' do
      allow(GlobalConfig).to receive(:get_value).and_call_original
      allow(GlobalConfig).to receive(:get_value).with('WEBHOOK_TIMEOUT').and_return('12')
      travel_to(base_time) do
        listener.message_created(event)
        perform_enqueued_jobs(at: base_time)
      end
      expect(deliveries.first.values_at(:open_timeout, :read_timeout)).to eq([12, 12])
    end
  end

  # Executa o job atual e os retries agendados até esgotar o retry_on do WebhookJob.
  # O adapter de teste agenda o retry com :at; usamos esse instante para o próximo passo.
  def drain_webhook_retries!
    10.times do
      entry = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |job| job[:job] == AgentBots::WebhookJob }
      break if entry.nil?

      at = entry[:at] ? Time.at(entry[:at]) : Time.current
      travel_to(at) { perform_enqueued_jobs(at: at) }
    end
  end

  describe 'success and failures' do
    it 'delivers 2xx once per bot and does not reopen the conversation' do
      travel_to(base_time) do
        listener.message_created(event)
        perform_enqueued_jobs(at: base_time)
      end
      expect(deliveries.size).to eq(2)
      expect(conversation.reload).to be_pending
    end

    context 'when the AgentBot answers 429 (3 responses)' do
      let(:scripted) { { assignee_url => Array.new(3) { SafeFetch::HttpError.new('429 Too Many Requests') } } }

      it 'retries 3 times in total and reopens only after exhaustion' do
        travel_to(base_time) { listener.message_created(event) }
        travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
        expect(conversation.reload).to be_pending

        travel_to(base_time + 4.seconds) { perform_enqueued_jobs(at: base_time + 4.seconds) }
        expect(conversation.reload).to be_pending

        travel_to(base_time + 8.seconds) { perform_enqueued_jobs(at: base_time + 8.seconds) }
        expect(deliveries.count { |delivery| delivery[:url] == assignee_url }).to eq(3)
        expect(conversation.reload).to be_open
      end

      it 'keeps delivery_id across attempts, but timestamp and signature change per attempt' do
        travel_to(base_time) { listener.message_created(event) }
        travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
        travel_to(base_time + 4.seconds) { perform_enqueued_jobs(at: base_time + 4.seconds) }
        attempts = deliveries.select { |delivery| delivery[:url] == assignee_url }
        expect(attempts.map { |delivery| delivery[:headers]['X-Chatwoot-Delivery'] }.uniq.size).to eq(1)
        expect(attempts.map { |delivery| delivery[:headers]['X-Chatwoot-Timestamp'] }).to eq(
          [base_time.to_i.to_s, (base_time + 4.seconds).to_i.to_s]
        )
        expect(attempts.map { |delivery| delivery[:headers]['X-Chatwoot-Signature'] }.uniq.size).to eq(2)
      end

      context 'when keep_pending_on_bot_failure is enabled' do
        it 'does not reopen the conversation' do
          account.update!(keep_pending_on_bot_failure: true)
          travel_to(base_time) { listener.message_created(event) }
          travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
          travel_to(base_time + 4.seconds) { perform_enqueued_jobs(at: base_time + 4.seconds) }
          travel_to(base_time + 8.seconds) { perform_enqueued_jobs(at: base_time + 8.seconds) }
          expect(conversation.reload).to be_pending
        end
      end
    end

    context 'when the AgentBot answers 500 (3 responses)' do
      let(:scripted) { { assignee_url => Array.new(3) { SafeFetch::HttpError.new('500 Internal Server Error') } } }

      it 'follows the same policy as 429: 3 attempts and reopen on exhaustion' do
        travel_to(base_time) { listener.message_created(event) }
        travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
        travel_to(base_time + 4.seconds) { perform_enqueued_jobs(at: base_time + 4.seconds) }
        travel_to(base_time + 8.seconds) { perform_enqueued_jobs(at: base_time + 8.seconds) }
        expect(deliveries.count { |delivery| delivery[:url] == assignee_url }).to eq(3)
        expect(conversation.reload).to be_open
      end
    end

    context 'when the AgentBot answers 404 (failure outside 429/500)' do
      let(:scripted) { { assignee_url => Array.new(5) { SafeFetch::HttpError.new('404 Not Found') } } }

      it 'keeps the conversation pending and schedules a retry while attempts remain' do
        travel_to(base_time) { listener.message_created(event) }
        travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
        expect(deliveries.count { |delivery| delivery[:url] == assignee_url }).to eq(1)
        expect(conversation.reload).to be_pending
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == AgentBots::WebhookJob }).to eq(1)
      end

      it 'reopens with a single activity only after the retries are exhausted' do
        travel_to(base_time) { listener.message_created(event) }
        travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
        drain_webhook_retries!

        activity = ActiveJob::Base.queue_adapter.enqueued_jobs + ActiveJob::Base.queue_adapter.performed_jobs
        expect(deliveries.count { |delivery| delivery[:url] == assignee_url }).to eq(5)
        expect(activity.count { |job| job[:job] == Conversations::ActivityMessageJob }).to eq(1)
        expect(conversation.reload).to be_open
      end

      context 'when keep_pending_on_bot_failure is enabled' do
        it 'does not reopen the conversation' do
          account.update!(keep_pending_on_bot_failure: true)
          travel_to(base_time) { listener.message_created(event) }
          travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
          drain_webhook_retries!
          expect(conversation.reload).to be_pending
        end
      end
    end

    context 'when the network times out (FetchError, mapped from Net::OpenTimeout in lib/safe_fetch.rb)' do
      let(:scripted) { { assignee_url => Array.new(5) { SafeFetch::FetchError.new('execution expired') } } }

      it 'follows the same retry policy as any other common failure' do
        travel_to(base_time) { listener.message_created(event) }
        travel_to(base_time) { perform_enqueued_jobs(at: base_time) }
        expect(deliveries.count { |delivery| delivery[:url] == assignee_url }).to eq(1)
        expect(conversation.reload).to be_pending

        drain_webhook_retries!

        expect(deliveries.count { |delivery| delivery[:url] == assignee_url }).to eq(5)
        expect(conversation.reload).to be_open
      end
    end
  end
end
