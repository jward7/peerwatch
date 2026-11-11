RSpec.describe Peerwatch::Client do
  let(:client) { described_class.new("https://bravo.example/") }
  let(:status_url) { "https://bravo.example/peerwatch/status" }

  it "returns the parsed body on a 200 and sends the Bearer token" do
    stub_request(:get, status_url)
      .with(headers: { "Authorization" => "Bearer secret", "User-Agent" => "peerwatch/#{Peerwatch::VERSION}" })
      .to_return(status: 200, body: { name: "bravo" }.to_json)

    reply = client.status

    expect(reply.kind).to eq(:ok)
    expect(reply.body).to eq("name" => "bravo")
  end

  it "reads a 503 as maintenance" do
    stub_request(:get, status_url).to_return(status: 503)

    expect(client.status.kind).to eq(:maintenance)
  end

  it "reads a 404 as unreachable" do
    stub_request(:get, status_url).to_return(status: 404)

    expect(client.status.kind).to eq(:unreachable)
  end

  it "reads an exception as unreachable" do
    stub_request(:get, status_url).to_raise(Errno::ECONNREFUSED)

    expect(client.status.kind).to eq(:unreachable)
  end

  it "never retries, so the configured timeouts are the real bound" do
    retries = nil
    allow_any_instance_of(Net::HTTP).to receive(:request) do |http, *|
      retries = http.max_retries
      Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable")
    end

    client.status

    expect(retries).to eq(0)
  end

  it "pushes registry rows as JSON" do
    stub = stub_request(:post, "https://bravo.example/peerwatch/registry")
      .with(body: { peers: [ { "name" => "charlie" } ] }.to_json,
            headers: { "Authorization" => "Bearer secret", "Content-Type" => "application/json" })
      .to_return(status: 200, body: { applied: 1 }.to_json)

    expect(client.push_registry([ { "name" => "charlie" } ]).kind).to eq(:ok)
    expect(stub).to have_been_requested
  end

  describe "address checks" do
    it "refuses a name that resolves to a private address: no request, so no token sent" do
      resolve_to("bravo.example", "192.168.1.1")
      stub = stub_request(:get, status_url).to_return(status: 200, body: "{}")

      reply = client.status

      expect(reply.kind).to eq(:unreachable)
      expect(reply.error_class).to eq("Peerwatch::Address::NotPublic")
      expect(stub).not_to have_been_requested
    end

    it "refuses when any one of several resolved addresses is not public" do
      resolve_to("bravo.example", "203.0.113.10", "fc00::1")
      stub = stub_request(:post, "https://bravo.example/peerwatch/registry")

      expect(client.push_registry([]).error_class).to eq("Peerwatch::Address::NotPublic")
      expect(stub).not_to have_been_requested
    end

    it "refuses a private IP literal without resolving it" do
      expect(Peerwatch::Address).not_to receive(:resolve)

      reply = described_class.new("https://169.254.169.254").registry

      expect(reply.kind).to eq(:unreachable)
      expect(reply.error_class).to eq("Peerwatch::Address::NotPublic")
    end

    it "pins the connection to the checked address, keeping the hostname for TLS" do
      resolve_to("bravo.example", "203.0.113.10")
      seen = nil
      allow_any_instance_of(Net::HTTP).to receive(:request) do |http, *|
        seen = [ http.address, http.ipaddr, http.use_ssl?, http.proxy? ]
        Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable")
      end

      client.status

      expect(seen).to eq([ "bravo.example", "203.0.113.10", true, false ])
    end
  end

  it "does not follow a redirect: one request, and the reply is unreachable" do
    first = stub_request(:get, status_url).to_return(status: 302, headers: { "Location" => "https://127.0.0.1/peerwatch/status" })

    expect(client.status.kind).to eq(:unreachable)
    expect(first).to have_been_requested.once
    expect(a_request(:get, "https://127.0.0.1/peerwatch/status")).not_to have_been_made
  end
end
