RSpec.describe Peerwatch::Peer do
  def build(**attrs)
    described_class.new({ name: "bravo", url: "https://bravo.example" }.merge(attrs))
  end

  describe "validations" do
    it "accepts a well-formed peer" do
      expect(build(contact_emails: [ "ops@example.com" ])).to be_valid
    end

    it "refuses http unless allow_http is set" do
      expect(build(url: "http://bravo.example")).not_to be_valid

      Peerwatch.config.allow_http = true
      expect(build(url: "http://bravo.example")).to be_valid
    end

    it "refuses a URL that is not http(s) with a host" do
      expect(build(url: "ftp://bravo.example")).not_to be_valid
      expect(build(url: "https://")).not_to be_valid
      expect(build(url: "not a url")).not_to be_valid
    end

    it "refuses a bad contact email" do
      peer = build(contact_emails: [ "ops@example.com", "not-an-email" ])

      expect(peer).not_to be_valid
      expect(peer.errors[:contact_emails]).to be_present
    end

    it "requires a lowercase name" do
      expect(build(name: "Bravo")).not_to be_valid
      expect(build(name: "-bravo")).not_to be_valid
      expect(build(name: "bravo two")).not_to be_valid
      expect(build(name: "bravo_2-b")).to be_valid
    end

    it "requires a unique name" do
      create_peer("bravo")

      expect(build).not_to be_valid
    end

    it "requires the health path to start with a slash" do
      expect(build(health_path: "up")).not_to be_valid
    end

    it "requires the health URL to parse" do
      peer = build(health_path: "/up now")

      expect(peer).not_to be_valid
      expect(peer.errors[:health_path]).to be_present
      expect(build(health_path: "/up?deep=1")).to be_valid
    end
  end

  describe "revision stamping" do
    it "stamps revision_at on every save" do
      peer = travel_to(Time.utc(2026, 1, 1, 10)) { create_peer("bravo") }
      expect(peer.revision_at).to eq(Time.utc(2026, 1, 1, 10))

      travel_to(Time.utc(2026, 1, 2, 10)) { peer.update!(environment: "production") }
      expect(peer.reload.revision_at).to eq(Time.utc(2026, 1, 2, 10))
    end

    it "keeps the given revision_at while syncing" do
      stamp = Time.utc(2025, 6, 1, 12, 0, 0, 123_456)
      peer = build(revision_at: stamp)
      peer.syncing = true
      peer.save!

      expect(peer.reload.revision_at).to eq(stamp)
    end
  end

  it "removes as a tombstone, never a delete" do
    peer = create_peer("bravo")

    peer.remove!

    expect(described_class.find_by(name: "bravo").removed_at).to be_present
    expect(described_class.live).to be_empty
  end

  describe ".new_or_revived" do
    it "builds a new peer when no removed peer has the name" do
      peer = described_class.new_or_revived(name: "bravo", url: "https://bravo.example")

      expect(peer).to be_new_record
      expect(peer.save).to be(true)
    end

    it "brings back a removed peer with the given attributes and a newer revision" do
      removed = travel_to(Time.utc(2026, 1, 1, 10)) { create_peer("bravo", environment: "old").tap(&:remove!) }

      peer = travel_to(Time.utc(2026, 1, 2, 10)) do
        described_class.new_or_revived("name" => "bravo", "url" => "https://bravo-new.example",
                                       "environment" => "production").tap(&:save!)
      end

      expect(peer.id).to eq(removed.id)
      expect(peer.reload).to have_attributes(removed_at: nil, url: "https://bravo-new.example",
                                             environment: "production", revision_at: Time.utc(2026, 1, 2, 10))
      expect(described_class.live.pluck(:name)).to eq([ "bravo" ])
    end

    it "does not touch a live peer of the same name" do
      create_peer("bravo")

      peer = described_class.new_or_revived(name: "bravo", url: "https://bravo.example")

      expect(peer).to be_new_record
      expect(peer).not_to be_valid
      expect(peer.errors[:name]).to include("has already been taken")
    end
  end

  it "parses contact emails from text" do
    peer = build
    peer.contact_emails_text = " ops@example.com\nadmin@example.com, ops@example.com ,,\n"

    expect(peer.contact_emails).to eq([ "ops@example.com", "admin@example.com" ])
    expect(peer.contact_emails_text).to eq("ops@example.com\nadmin@example.com")
  end

  it "knows its maintenance window, health URL and whether it is this app" do
    peer = build(url: "https://bravo.example/", maintenance_until: 10.minutes.from_now)

    expect(peer.in_maintenance?).to be(true)
    expect(peer.in_maintenance?(11.minutes.from_now)).to be(false)
    expect(peer.health_url).to eq("https://bravo.example/up")
    expect(peer.self?).to be(false)
    expect(build(name: "alpha").self?).to be(true)
  end
end
