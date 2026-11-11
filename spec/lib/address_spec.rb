RSpec.describe Peerwatch::Address do
  describe ".public?" do
    {
      "10.0.0.1" => false,             # RFC 1918
      "172.16.0.1" => false,           # RFC 1918
      "192.168.1.1" => false,          # RFC 1918
      "127.0.0.1" => false,            # loopback
      "169.254.169.254" => false,      # link-local, cloud metadata services
      "0.0.0.0" => false,              # unspecified
      "100.100.100.200" => false,      # shared address space, also used for metadata
      "224.0.0.1" => false,            # multicast
      "255.255.255.255" => false,      # broadcast
      "::" => false,                   # unspecified
      "::1" => false,                  # loopback
      "fe80::1" => false,              # link-local
      "fe80::1%eth0" => false,         # link-local with a zone id
      "fc00::1" => false,              # unique local
      "fd12:3456::1" => false,         # unique local
      "ff02::1" => false,              # multicast
      "::ffff:127.0.0.1" => false,     # IPv4-mapped loopback
      "::ffff:169.254.169.254" => false, # IPv4-mapped link-local
      "::ffff:10.0.0.1" => false,      # IPv4-mapped private
      "64:ff9b::a9fe:a9fe" => false,   # NAT64 form of 169.254.169.254
      "203.0.113.10" => true,          # documentation range: public for this check
      "192.0.2.1" => true,             # documentation range: public for this check
      "198.51.100.7" => true,          # documentation range: public for this check
      "2001:db8::1" => true,           # documentation range: public for this check
      "3fff::1" => true,               # global unicast (the RFC 9637 documentation range)
      "::ffff:203.0.113.10" => true,   # IPv4-mapped public
      "[2001:db8::1]" => true          # bracketed, as in a URL
    }.each do |address, expected|
      it "is #{expected} for #{address}" do
        expect(described_class.public?(address)).to be(expected)
      end
    end

    it "is false for anything that is not an address" do
      [ nil, "", "bravo.example", "999.1.1.1", "203.0.113.0/24", "not an ip" ].each do |value|
        expect(described_class.public?(value)).to be(false), value.inspect
      end
    end
  end

  describe ".localhost_name?" do
    it "matches localhost and *.localhost, in any case, with a trailing dot" do
      expect(%w[localhost LOCALHOST localhost. api.localhost].map { |h| described_class.localhost_name?(h) }).to all(be(true))
      expect(%w[localhost.example notlocalhost bravo.example].map { |h| described_class.localhost_name?(h) }).to all(be(false))
    end
  end

  describe ".dial_address" do
    let(:config) { Peerwatch.config }

    it "returns the checked address for a name that resolves to public addresses" do
      resolve_to("bravo.example", "203.0.113.10")

      expect(described_class.dial_address("bravo.example", config: config)).to eq("203.0.113.10")
    end

    it "prefers IPv4 when both families resolve" do
      resolve_to("bravo.example", "2001:db8::5", "203.0.113.10")

      expect(described_class.dial_address("bravo.example", config: config)).to eq("203.0.113.10")
    end

    it "raises NotPublic when any resolved address is not public" do
      resolve_to("bravo.example", "203.0.113.10", "10.0.0.1")

      expect { described_class.dial_address("bravo.example", config: config) }.to raise_error(described_class::NotPublic)
    end

    it "raises NotPublic when nothing resolves" do
      resolve_to("bravo.example")

      expect { described_class.dial_address("bravo.example", config: config) }.to raise_error(described_class::NotPublic)
    end

    it "checks a given ip instead of resolving" do
      expect(described_class).not_to receive(:resolve)

      expect(described_class.dial_address("bravo.example", ip: "203.0.113.10", config: config)).to eq("203.0.113.10")
      expect { described_class.dial_address("bravo.example", ip: "127.0.0.1", config: config) }
        .to raise_error(described_class::NotPublic)
    end

    it "pins nothing, and resolves nothing, when private addresses are allowed" do
      config.allow_private_addresses = true
      expect(described_class).not_to receive(:resolve)

      expect(described_class.dial_address("localhost", config: config)).to be_nil
      expect(described_class.dial_address("bravo.example", ip: "10.0.0.1", config: config)).to eq("10.0.0.1")
    end

    it "bounds resolution by open_timeout" do
      config.open_timeout = 0.05
      allow(described_class).to receive(:resolve).with("bravo.example") { sleep 1 }

      expect { described_class.dial_address("bravo.example", config: config) }.to raise_error(Net::OpenTimeout)
    end
  end

  describe ".resolve" do
    it "returns the addresses for a name (an IP literal here, so no resolver is asked)" do
      allow(described_class).to receive(:resolve).and_call_original

      expect(described_class.resolve("203.0.113.10")).to eq([ "203.0.113.10" ])
    end
  end
end
