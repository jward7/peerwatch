require "ipaddr"
require "socket"
require "timeout"
require "net/protocol"

module Peerwatch
  # The one home for "may this app send a request to that address?". Registry
  # rows come from whoever holds the shared token, so every URL and IP in them
  # is untrusted: unless allow_private_addresses is set, Peerwatch only ever
  # connects to public addresses. Plain Ruby, stdlib only.
  module Address
    # Raised inside Probe and Client, and caught there: a refused request is
    # a failed check or an :unreachable reply, never an exception.
    class NotPublic < StandardError; end

    # Loopback, private, link-local, unspecified, multicast and the other
    # ranges that are never a peer's public address. The documentation ranges
    # (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32) are
    # deliberately absent: they are public as far as this check goes.
    REFUSED_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
      192.168.0.0/16 224.0.0.0/4 240.0.0.0/4
      ::/96 fc00::/7 fe80::/10 fec0::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    # IPv6 forms that carry an IPv4 address in their last 32 bits: IPv4-mapped
    # and NAT64. The embedded address is checked instead.
    EMBEDDING_RANGES = %w[::ffff:0:0/96 64:ff9b::/96].map { |range| IPAddr.new(range) }.freeze

    module_function

    # True for an address this app may connect to. False for anything refused
    # and for anything that does not parse as an IP address.
    def public?(address)
      ip = parse(address)
      return false if ip.nil?

      if ip.ipv6? && EMBEDDING_RANGES.any? { |range| range.include?(ip) }
        ip = IPAddr.new(ip.to_i & 0xffff_ffff, Socket::AF_INET)
      end
      REFUSED_RANGES.none? { |range| range.family == ip.family && range.include?(ip) }
    end

    # An IPAddr, or nil when address is not an IP address. A zone id
    # ("fe80::1%eth0") is dropped: it does not change which range it is in.
    def parse(address)
      text = address.to_s.strip.delete_prefix("[").delete_suffix("]").sub(/%.*\z/, "")
      # A prefix ("192.0.2.0/24") is a range, not an address to dial.
      text.empty? || text.include?("/") ? nil : IPAddr.new(text)
    rescue IPAddr::Error
      nil
    end

    def ip_literal?(host)
      !parse(host).nil?
    end

    # localhost and *.localhost name this machine whatever DNS says (RFC 6761).
    def localhost_name?(host)
      name = normalize_host(host)
      name == "localhost" || name.end_with?(".localhost")
    end

    # Lowercase, without brackets or a trailing dot, for comparing names.
    def normalize_host(host)
      host.to_s.strip.delete_prefix("[").delete_suffix("]").downcase.delete_suffix(".")
    end

    # The address to connect to for host, already checked, for
    # Net::HTTP#ipaddr= so the name cannot re-resolve to something else
    # between the check and the connect. With ip:, that stored address is
    # checked and used instead of resolving host. Returns nil only when
    # private addresses are allowed and there is nothing to pin, meaning
    # "connect as Net::HTTP normally would". Raises NotPublic when refused.
    def dial_address(host, ip: nil, config: Peerwatch.config)
      ip = ip.to_s.strip
      return ip.empty? ? nil : ip if config.allow_private_addresses

      addresses = ip.empty? ? addresses_for(host, config) : [ ip ]
      refused = addresses.reject { |address| public?(address) }
      raise NotPublic, "#{host} resolves to no address" if addresses.empty?
      raise NotPublic, "#{host} resolves to a non-public address (#{refused.join(", ")})" if refused.any?

      # One address has to be chosen. IPv4 first: a host without working
      # IPv6 would otherwise fail every check of a dual-stack peer.
      addresses.find { |address| parse(address).ipv4? } || addresses.first
    end

    def addresses_for(host, config)
      name = normalize_host(host)
      return [ name ] if ip_literal?(name)
      raise NotPublic, "#{name} names this machine" if localhost_name?(name)

      # Bounded like the connect it replaces: Net::HTTP resolves inside its
      # own open_timeout.
      Timeout.timeout(config.open_timeout, Net::OpenTimeout) { resolve(name) }
    end

    # Every address the name resolves to. The seam the specs stub, so no
    # spec ever needs a real resolver.
    def resolve(name)
      Addrinfo.getaddrinfo(name, nil, nil, :STREAM).map(&:ip_address).uniq
    end
  end
end
