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

    describe "this app's rules" do
      it "requires a stored ip to be a public address" do
        expect(build(ip: "203.0.113.10")).to be_valid
        expect(build(ip: "2001:db8::10")).to be_valid
        %w[10.0.0.1 127.0.0.1 169.254.169.254 ::1 fe80::1 ::ffff:127.0.0.1].each do |ip|
          peer = build(ip: ip)
          expect(peer).not_to be_valid, ip
          expect(peer.errors[:ip]).to include("must be a public address")
        end
      end

      it "requires a stored ip to parse" do
        peer = build(ip: "bravo.example")

        expect(peer).not_to be_valid
        expect(peer.errors[:ip]).to include("is not an IP address")
      end

      it "refuses a URL whose host is a non-public IP literal" do
        expect(build(url: "https://203.0.113.10")).to be_valid
        %w[https://10.0.0.1 https://169.254.169.254 https://[::1] https://[fc00::1]:8443].each do |url|
          peer = build(url: url)
          expect(peer).not_to be_valid, url
          expect(peer.errors[:url]).to include("must not point at a loopback, private or link-local address")
        end
      end

      it "refuses localhost and *.localhost" do
        %w[https://localhost https://LOCALHOST:3000 https://api.localhost].each do |url|
          peer = build(url: url)
          expect(peer).not_to be_valid, url
          expect(peer.errors[:url]).to include("must not point at localhost")
        end
      end

      it "relaxes only the address rules when allow_private_addresses is set" do
        Peerwatch.config.allow_private_addresses = true
        Peerwatch.config.allow_http = true
        Peerwatch.config.allowed_peer_hosts = %w[localhost]
        Peerwatch.config.allowed_contact_domains = %w[example.com]

        expect(build(url: "http://localhost:3001", ip: "127.0.0.1", contact_emails: [ "ops@example.com" ])).to be_valid
        expect(build(url: "http://localhost:3001", ip: "not an ip")).not_to be_valid
        expect(build(url: "http://127.0.0.1:3001")).not_to be_valid # not in allowed_peer_hosts
        expect(build(url: "http://localhost:3001", contact_emails: [ "ops@example.net" ])).not_to be_valid
      end

      it "requires the URL's host to be in allowed_peer_hosts when set, ignoring case" do
        Peerwatch.config.allowed_peer_hosts = %w[Bravo.Example charlie.example]

        expect(build(url: "https://bravo.example")).to be_valid
        expect(build(url: "https://BRAVO.EXAMPLE/")).to be_valid
        peer = build(url: "https://evil.bravo.example")
        expect(peer).not_to be_valid
        expect(peer.errors[:url]).to include("host is not in this app's allowed_peer_hosts")
      end

      it "requires every contact to be at an allowed_contact_domains domain when set, ignoring case" do
        Peerwatch.config.allowed_contact_domains = %w[Example.com]

        expect(build(contact_emails: [ "ops@example.com", "Admin@EXAMPLE.COM" ])).to be_valid
        expect(build(contact_emails: [])).to be_valid
        [ "ops@example.net", "ops@sub.example.com", "ops@example.com.example.net" ].each do |email|
          peer = build(contact_emails: [ "ops@example.com", email ])
          expect(peer).not_to be_valid, email
          expect(peer.errors[:contact_emails]).to include("must all be at a domain in this app's allowed_contact_domains")
        end
      end

      it "treats nil allowlists as any" do
        expect(build(url: "https://anything.example", contact_emails: [ "ops@anywhere.example" ])).to be_valid
      end
    end
  end

  describe "#permitted?" do
    it "applies the same rules to a row already saved, so tightening them blocks it" do
      peer = create_peer("bravo", contact_emails: [ "ops@example.com" ])
      expect(peer.permitted?).to be(true)
      expect(peer.blocked_reasons).to be_empty

      Peerwatch.config.allowed_peer_hosts = %w[charlie.example]
      Peerwatch.config.allowed_contact_domains = %w[example.net]

      expect(peer.permitted?).to be(false)
      expect(peer.blocked_reasons).to eq([ "Url host is not in this app's allowed_peer_hosts",
                                           "Contact emails must all be at a domain in this app's allowed_contact_domains" ])
      expect(peer.errors).to be_empty
    end

    it "blocks a private address that was saved while private addresses were allowed" do
      Peerwatch.config.allow_private_addresses = true
      peer = create_peer("bravo", ip: "10.0.0.1")
      Peerwatch.config.allow_private_addresses = false

      expect(peer.reload.permitted?).to be(false)
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
