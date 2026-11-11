RSpec.describe Peerwatch::RegistryMerge do
  def row(name, revision_at, **attrs)
    { "name" => name, "url" => "https://#{name}.example", "health_path" => "/up",
      "contact_emails" => [ "ops@example.com" ], "revision_at" => revision_at.utc.iso8601(6) }
      .merge(attrs.stringify_keys)
  end

  let(:earlier) { Time.utc(2026, 1, 1, 10, 0, 0, 111_111) }
  let(:later) { Time.utc(2026, 1, 2, 10, 0, 0, 222_222) }

  it "creates an unknown peer and keeps its revision_at" do
    expect(described_class.call([ row("bravo", earlier, environment: "production") ])).to eq(1)

    peer = Peerwatch::Peer.find_by!(name: "bravo")
    expect(peer.environment).to eq("production")
    expect(peer.revision_at).to eq(earlier)
  end

  it "applies a newer row" do
    described_class.call([ row("bravo", earlier) ])

    expect(described_class.call([ row("bravo", later, environment: "staging") ])).to eq(1)
    expect(Peerwatch::Peer.find_by!(name: "bravo").environment).to eq("staging")
  end

  it "ignores an older or equal row" do
    described_class.call([ row("bravo", later, environment: "production") ])

    expect(described_class.call([ row("bravo", earlier, environment: "older") ])).to eq(0)
    expect(described_class.call([ row("bravo", later, environment: "equal") ])).to eq(0)
    expect(Peerwatch::Peer.find_by!(name: "bravo").environment).to eq("production")
  end

  it "rejects a row stamped too far in the future" do
    described_class.call([ row("bravo", earlier, environment: "production") ])
    far = Time.current + described_class::MAX_CLOCK_SKEW + 1.minute

    expect(described_class.call([ row("bravo", far, environment: "fast-clock") ])).to eq(0)
    expect(described_class.call([ row("charlie", far) ])).to eq(0)
    expect(Peerwatch::Peer.find_by!(name: "bravo").environment).to eq("production")
    expect(Peerwatch::Peer.exists?(name: "charlie")).to be(false)
  end

  it "accepts a row within the allowed clock skew" do
    slightly_ahead = Time.current + 1.minute

    expect(described_class.call([ row("bravo", slightly_ahead) ])).to eq(1)
  end

  it "syncs a tombstone" do
    described_class.call([ row("bravo", earlier) ])

    described_class.call([ row("bravo", later, removed_at: later.iso8601(6)) ])

    expect(Peerwatch::Peer.live).to be_empty
    expect(Peerwatch::Peer.find_by!(name: "bravo").removed_at).to eq(later)
  end

  it "skips bad rows without stopping the rest" do
    rows = [
      row("Bad Name", earlier),
      row("charlie", earlier, url: "http://charlie.example"),
      row("delta", earlier, contact_emails: [ "nope" ]),
      { "name" => "echo" },
      "not a hash",
      row("bravo", earlier)
    ]

    expect(described_class.call(rows)).to eq(1)
    expect(Peerwatch::Peer.pluck(:name)).to eq([ "bravo" ])
  end

  it "skips a row that breaks this app's rules, logging the peer and the reason, and applies the rest" do
    Peerwatch.config.allowed_peer_hosts = %w[bravo.example charlie.example delta.example foxtrot.example]
    Peerwatch.config.allowed_contact_domains = %w[example.com]
    logged = []
    allow(Rails.logger).to receive(:warn) { |message| logged << message }
    rows = [
      row("bravo", earlier),
      row("charlie", earlier, contact_emails: [ "someone@example.net" ]),
      row("delta", earlier, ip: "169.254.169.254"),
      row("echo", earlier),
      row("foxtrot", earlier, url: "https://10.0.0.1")
    ]

    expect(described_class.call(rows)).to eq(1)
    expect(Peerwatch::Peer.pluck(:name)).to eq([ "bravo" ])
    expect(logged).to include(
      a_string_including('"charlie"', "allowed_contact_domains"),
      a_string_including('"delta"', "Ip must be a public address"),
      a_string_including('"echo"', "allowed_peer_hosts"),
      a_string_including('"foxtrot"', "loopback, private or link-local")
    )
    expect(logged.join).not_to include("secret", "someone@example.net")
  end

  it "keeps the existing row when a newer one breaks this app's rules" do
    described_class.call([ row("bravo", earlier, environment: "production") ])
    Peerwatch.config.allowed_contact_domains = %w[example.com]

    expect(described_class.call([ row("bravo", later, contact_emails: [ "ops@example.net" ]) ])).to eq(0)
    expect(Peerwatch::Peer.find_by!(name: "bravo")).to have_attributes(environment: "production",
                                                                       contact_emails: [ "ops@example.com" ])
  end

  it "returns zero for something that is not a list" do
    expect(described_class.call(nil)).to eq(0)
    expect(described_class.call("peers")).to eq(0)
  end

  it "round-trips revision_at exactly through registry_row" do
    original = create_peer("bravo", contact_emails: [ "ops@example.com" ], maintenance_until: later)
    exported = original.registry_row
    original.destroy!

    described_class.call([ exported ])
    copy = Peerwatch::Peer.find_by!(name: "bravo")

    expect(copy.revision_at).to eq(original.revision_at)
    expect(copy.registry_row).to eq(exported)
    # Equal revision: the same row again is a no-op.
    expect(described_class.call([ copy.registry_row ])).to eq(0)
  end
end
