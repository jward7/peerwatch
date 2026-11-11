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
    # WebMock matches on the hostname and cannot see ipaddr=, so stub one
    # level down. A failing name fails where it really would: at resolution.
    def answer(by_name:, by_ip:)
      if by_name == :fail
        allow(Peerwatch::Address).to receive(:resolve).with("bravo.example").and_raise(SocketError, "getaddrinfo failed")
      end
      allow_any_instance_of(Net::HTTP).to receive(:request_get) do |http, *|
        raise Errno::ECONNREFUSED if http.ipaddr == "192.0.2.10" && by_ip == :fail

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

    it "never falls back to a stored address that is not public" do
      answer(by_name: :fail, by_ip: :ok)
      dialled = []
      allow_any_instance_of(Net::HTTP).to receive(:request_get) { |http, *| dialled << http.ipaddr }

      outcome = described_class.call(url: url, ip: "10.0.0.1")

      expect(outcome.ok?).to be(false)
      expect(outcome.error_class).to eq("SocketError")
      expect(outcome.cause).to eq("unknown")
      expect(dialled).to be_empty
    end
  end

  describe "address checks" do
    it "refuses a name that resolves to a private address, without a request" do
      resolve_to("bravo.example", "10.0.0.5")
      stub = stub_request(:get, url).to_return(status: 200)

      outcome = described_class.call(url: url, ip: nil)

      expect(outcome.ok?).to be(false)
      expect(outcome.error_class).to eq("Peerwatch::Address::NotPublic")
      expect(outcome.cause).to eq("unknown")
      expect(stub).not_to have_been_requested
    end

    it "refuses when any one of several resolved addresses is not public" do
      resolve_to("bravo.example", "203.0.113.10", "169.254.169.254")
      stub = stub_request(:get, url).to_return(status: 200)

      expect(described_class.call(url: url, ip: nil).error_class).to eq("Peerwatch::Address::NotPublic")
      expect(stub).not_to have_been_requested
    end

    it "does not try the stored address after refusing the name" do
      resolve_to("bravo.example", "127.0.0.1")
      dialled = []
      allow_any_instance_of(Net::HTTP).to receive(:request_get) { |http, *| dialled << http.ipaddr }

      outcome = described_class.call(url: url, ip: "192.0.2.10")

      expect(outcome.error_class).to eq("Peerwatch::Address::NotPublic")
      expect(dialled).to be_empty
    end

    it "refuses a private IP literal or localhost in the URL without resolving anything" do
      expect(Peerwatch::Address).not_to receive(:resolve)

      %w[https://127.0.0.1/up https://[::1]/up https://localhost/up https://api.localhost/up].each do |refused|
        expect(described_class.call(url: refused, ip: nil).error_class).to eq("Peerwatch::Address::NotPublic"), refused
      end
    end

    it "pins the connection to the checked address, keeping the hostname for TLS" do
      resolve_to("bravo.example", "2001:db8::5", "203.0.113.10")
      seen = nil
      allow_any_instance_of(Net::HTTP).to receive(:request_get) do |http, *|
        seen = [ http.address, http.ipaddr, http.use_ssl?, http.proxy? ]
        Net::HTTPOK.new("1.1", "200", "OK")
      end

      expect(described_class.call(url: url, ip: nil).ok?).to be(true)
      # IPv4 is preferred when both families resolve; no proxy could re-resolve the name.
      expect(seen).to eq([ "bravo.example", "203.0.113.10", true, false ])
    end

    it "pins to a public IPv6 address when that is all there is" do
      resolve_to("bravo.example", "2001:db8::5")
      seen = nil
      allow_any_instance_of(Net::HTTP).to receive(:request_get) do |http, *|
        seen = http.ipaddr
        Net::HTTPOK.new("1.1", "200", "OK")
      end

      described_class.call(url: url, ip: nil)

      expect(seen).to eq("2001:db8::5")
    end

    it "connects to private addresses when allow_private_addresses is set" do
      Peerwatch.config.allow_private_addresses = true
      resolve_to("bravo.example", "10.0.0.5")
      stub = stub_request(:get, url).to_return(status: 200)

      expect(described_class.call(url: url, ip: nil).ok?).to be(true)
      expect(stub).to have_been_requested
    end
  end

  it "does not follow a redirect: a 3xx is simply not up" do
    first = stub_request(:get, url).to_return(status: 301, headers: { "Location" => "https://169.254.169.254/latest" })

    outcome = described_class.call(url: url, ip: nil)

    expect(outcome.ok?).to be(false)
    expect(outcome.status_code).to eq(301)
    expect(first).to have_been_requested.once
    expect(a_request(:get, "https://169.254.169.254/latest")).not_to have_been_made
  end
end
