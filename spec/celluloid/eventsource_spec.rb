require 'spec_helper'

TIMEOUT = 0.0001

RSpec.describe Celluloid::EventSource do
  let(:data) { "foo bar " }

  def with_sse_server
    server = ServerSentEvents.new
    yield server
  ensure
    server.terminate if server && server.alive?
  end

  describe '#initialize' do
    let(:url)  { "example.com" }

    it 'runs asynchronously' do
      ces = double(Celluloid::EventSource)
      expect_any_instance_of(Celluloid::EventSource).to receive_message_chain(:async, :listen).and_return(ces)

      Celluloid::EventSource.new("http://#{url}")
    end

    it 'allows customizing headers' do
      auth_header = { "Authorization" => "Basic aGVsbG86dzBybGQh" }

      allow_any_instance_of(Celluloid::EventSource).to receive_message_chain(:async, :listen)
      es = Celluloid::EventSource.new("http://#{url}", :headers => auth_header)

      headers = es.instance_variable_get('@headers')
      expect(headers['Authorization']).to eq(auth_header["Authorization"])
    end
  end

  it "keeps track of last event id" do
    with_sse_server do |server|
      @last_event_id = ""
      ces = Celluloid::EventSource.new("http://localhost:63310") do |conn|
        conn.on_message { |event| @last_event_id = event.last_event_id }
      end

      sleep TIMEOUT until ces.connected?

      expect { server.broadcast(nil, data); sleep TIMEOUT }.to change { @last_event_id }.to("1")
    end
  end

  it "ignores comment ':' lines" do
    with_sse_server do |server|
      expect { |event|
        ces = Celluloid::EventSource.new("http://localhost:63310") do |conn|
          conn.on_message(&event)
        end

        sleep TIMEOUT until ces.connected?

        server.send_ping

        sleep TIMEOUT
      }.to_not yield_control
    end
  end

  it 'receives data through message event' do
    with_sse_server do |server|
      expect { |event|
        ces = Celluloid::EventSource.new("http://localhost:63310") do |conn|
          conn.on_message(&event)
        end

        sleep TIMEOUT until ces.connected?

        server.broadcast(nil, data)

        sleep TIMEOUT
      }.to yield_with_args(Celluloid::EventSource::MessageEvent)
    end
  end

  it 'receives response body through error event' do
    with_sse_server do |server|
      expect { |error|
        ces = Celluloid::EventSource.new("http://localhost:63310/error") do |conn|
          conn.on_error(&error)
        end

        sleep TIMEOUT until ces.closed?

      }.to yield_with_args({status_code: 400, body:"blop"})
    end
  end

  it 'receives response without a body through error event' do
    with_sse_server do |server|
      expect { |error|
        ces = Celluloid::EventSource.new("http://localhost:63310/error/no_body") do |conn|
          conn.on_error(&error)
        end

        sleep TIMEOUT until ces.closed?

      }.to yield_with_args({status_code: 400, body:""})
    end
  end

  it 'receives custom events through event handlers' do
    with_sse_server do |server|
      event_name = :custom_event

      expect { |event|
        ces = Celluloid::EventSource.new("http://localhost:63310") do |conn|
          conn.on(event_name, &event)
        end

        sleep TIMEOUT until ces.connected?

        server.broadcast(event_name, data)

        sleep TIMEOUT
      }.to yield_with_args(Celluloid::EventSource::MessageEvent)
    end
  end

end
