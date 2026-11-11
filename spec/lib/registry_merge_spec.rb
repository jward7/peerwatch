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
