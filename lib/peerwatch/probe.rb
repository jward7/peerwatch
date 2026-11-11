require "net/http"
require "uri"
require "peerwatch/address"

module Peerwatch
  # One health request to one peer. Plain Ruby: no Rails, no database, never
  # raises. The caller decides what the outcome means.
  #
  # The URL and IP come from the registry, which anyone holding the token can
  # write, so every request goes through Address first: a name that resolves
  # to a non-public address is a failed check, and the connection is pinned
  # to the address that was checked. Redirects are never followed.
  class Probe
    Outcome = Struct.new(:ok, :status_code, :latency_ms, :error_class, :cause, keyword_init: true) do
      def ok? = ok
    end

    NOT_PUBLIC = Address::NotPublic.name

    def self.call(...) = new(...).call

    def initialize(url:, ip: nil, config: Peerwatch.config)
      @url = url
      @ip = ip.to_s.strip
      @config = config
    end

    def call
      # Parsed here, not in initialize, so a bad URL is a failed check
      # rather than an exception.
      @uri = URI.parse(@url)
      first = request
      return first if first.ok? || @ip.empty? || first.error_class == NOT_PUBLIC

      # The name failed. Ask the stored address directly: if that answers,
      # the app is fine and the name is what broke.
      via_ip = request(ipaddr: @ip)
      # A stored address that is itself refused says nothing about the name.
      return first if via_ip.error_class == NOT_PUBLIC

      first.cause = via_ip.ok? ? "dns" : "app"
      first
    rescue StandardError => e
      Outcome.new(ok: false, error_class: e.class.name, cause: "unknown")
    end

    private

    def request(ipaddr: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      dial = Address.dial_address(@uri.hostname, ip: ipaddr, config: @config)
      # No proxy (nil): a proxy would resolve the name itself, and the pin
      # below would not hold.
      http = Net::HTTP.new(@uri.hostname, @uri.port, nil)
      http.use_ssl = @uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      # Net::HTTP retries a timed-out GET once by default, doubling the
      # timeouts. failure_threshold already absorbs a one-off failure.
      http.max_retries = 0
      # ipaddr= dials the checked address but keeps the hostname for SNI and
      # certificate verification, so pinning loses no strictness.
      http.ipaddr = dial if dial

      response = http.request_get(@uri.request_uri, "User-Agent" => @config.user_agent)
      code = response.code.to_i
      Outcome.new(ok: code.between?(200, 299), status_code: code, latency_ms: elapsed_ms(started),
                  cause: code.between?(200, 299) ? nil : "app")
    rescue StandardError => e
      Outcome.new(ok: false, latency_ms: elapsed_ms(started), error_class: e.class.name, cause: "unknown")
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end
  end
end
