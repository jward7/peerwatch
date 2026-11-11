RSpec.describe Peerwatch::Sync do
  def registry_body(*rows)
    { peers: rows }.to_json
  end

  describe ".sources" do
    it "lists live peers except self, plus the seed, once each" do
      create_peer("alpha")
      create_peer("bravo")
      create_peer("charlie").remove!
      Peerwatch.config.seed_url = "https://bravo.example/"

      expect(described_class.sources).to eq([ "https://bravo.example" ])

      Peerwatch.config.seed_url = "https://delta.example"
      expect(described_class.sources).to eq([ "https://bravo.example", "https://delta.example" ])
    end
  end

  describe ".pull" do
    it "joins via the seed URL" do
      Peerwatch.config.seed_url = "https://bravo.example"
      row = { "name" => "bravo", "url" => "https://bravo.example", "health_path" => "/up",
              "contact_emails" => [], "revision_at" => Time.current.iso8601(6) }
      stub_request(:get, "https://bravo.example/peerwatch/registry").to_return(status: 200, body: registry_body(row))

      expect(described_class.pull).to eq(1)
      expect(Peerwatch::Peer.pluck(:name)).to eq([ "bravo" ])
    end

    it "uses replies already fetched" do
      row = { "name" => "charlie", "url" => "https://charlie.example", "revision_at" => Time.current.iso8601(6) }
      replies = [ Peerwatch::Client::Reply.new(kind: :ok, body: { "peers" => [ row ] }),
                  Peerwatch::Client::Reply.new(kind: :unreachable) ]

      expect(described_class.pull(replies)).to eq(1)
    end

    it "does nothing without a token" do
      Peerwatch.config.token = nil
      Peerwatch.config.seed_url = "https://bravo.example"

      expect(described_class.pull).to eq(0)
    end
  end

  describe ".push" do
    it "sends the row to every live peer except self and counts the acceptances" do
      alpha = create_peer("alpha")
      create_peer("bravo")
      create_peer("charlie")
      create_peer("delta").remove!
      stub_request(:post, "https://bravo.example/peerwatch/registry").to_return(status: 200, body: "{}")
      charlie = stub_request(:post, "https://charlie.example/peerwatch/registry").to_raise(Errno::ECONNREFUSED)

      expect(described_class.push(alpha)).to eq(1)
      expect(a_request(:post, "https://bravo.example/peerwatch/registry").with { |req| JSON.parse(req.body)["peers"].map { |r| r["name"] } == [ "alpha" ] }).to have_been_made
      expect(charlie).to have_been_requested
    end

    it "does nothing without a token" do
      Peerwatch.config.token = ""
      create_peer("bravo")

      expect(described_class.push(create_peer("alpha"))).to eq(0)
    end
  end
end
