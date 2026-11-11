RSpec.describe Peerwatch::Probe do
  let(:url) { "https://bravo.example/up" }

  it "is ok on a 200" do
    stub_request(:get, url).with(headers: { "User-Agent" => "peerwatch/#{Peerwatch::VERSION}" }).to_return(status: 200)

    outcome = described_class.call(url: url, ip: nil)

    expect(outcome.ok?).to be(true)
    expect(outcome.status_code).to eq(200)
    expect(outcome.latency_ms).to be >= 0
    expect(outcome.cause).to be_nil
  end

  it "is not ok on a 500, blaming the app" do
    stub_request(:get, url).to_return(status: 500)

    outcome = described_class.call(url: url, ip: nil)

    expect(outcome.ok?).to be(false)
    expect(outcome.status_code).to eq(500)
    expect(outcome.cause).to eq("app")
  end

  it "is not ok on a timeout" do
    stub_request(:get, url).to_timeout

    outcome = described_class.call(url: url, ip: nil)

    expect(outcome.ok?).to be(false)
    expect(outcome.error_class).to eq("Net::OpenTimeout")
    expect(outcome.cause).to eq("unknown")
  end

  it "is not ok when the name does not resolve" do
    stub_request(:get, url).to_raise(SocketError)

    outcome = described_class.call(url: url, ip: nil)

    expect(outcome.ok?).to be(false)
    expect(outcome.error_class).to eq("SocketError")
  end

  it "applies the configured timeouts and never retries, so they are the real bound" do
    Peerwatch.config.open_timeout = 3
    Peerwatch.config.read_timeout = 4
    seen = nil
    allow_any_instance_of(Net::HTTP).to receive(:request_get) do |http, *|
      seen = [ http.open_timeout, http.read_timeout, http.max_retries ]
      Net::HTTPOK.new("1.1", "200", "OK")
    end

    described_class.call(url: url, ip: nil)

    expect(seen).to eq([ 3, 4, 0 ])
  end

  it "is not ok, and does not raise, when the URL cannot be parsed" do
    outcome = described_class.call(url: "https://bravo.example/up now", ip: nil)

    expect(outcome.ok?).to be(false)
    expect(outcome.error_class).to eq("URI::InvalidURIError")
    expect(outcome.cause).to eq("unknown")
  end

  describe "IP fallback" do
    # WebMock matches on the hostname and cannot see ipaddr=, so stub one level down.
    def answer(by_name:, by_ip:)
      allow_any_instance_of(Net::HTTP).to receive(:request_get) do |http, *|
        answers = http.ipaddr ? by_ip : by_name
        raise SocketError, "getaddrinfo failed" if answers == :fail

        Net::HTTPOK.new("1.1", "200", "OK")
      end
    end

    it "blames DNS when the stored address answers" do
      answer(by_name: :fail, by_ip: :ok)

      outcome = described_class.call(url: url, ip: "192.0.2.10")

      expect(outcome.ok?).to be(false)
      expect(outcome.cause).to eq("dns")
    end

    it "blames the app when the stored address fails too" do
      answer(by_name: :fail, by_ip: :fail)

      outcome = described_class.call(url: url, ip: "192.0.2.10")

      expect(outcome.ok?).to be(false)
      expect(outcome.cause).to eq("app")
    end

    it "does not retry when the first request succeeds" do
      answer(by_name: :ok, by_ip: :fail)

      expect(described_class.call(url: url, ip: "192.0.2.10").ok?).to be(true)
    end
  end
end
