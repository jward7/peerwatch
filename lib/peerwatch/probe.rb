require "net/http"
require "uri"

module Peerwatch
  # One health request to one peer. Plain Ruby: no Rails, no database, never
  # raises. The caller decides what the outcome means.
  class Probe
    Outcome = Struct.new(:ok, :status_code, :latency_ms, :error_class, :cause, keyword_init: true) do
      def ok? = ok
    end

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
      return first if first.ok? || @ip.empty?

      # The name failed. Ask the stored address directly: if that answers,
      # the app is fine and the name is what broke.
      via_ip = request(ipaddr: @ip)
      first.cause = via_ip.ok? ? "dns" : "app"
      first
    rescue StandardError => e
      Outcome.new(ok: false, error_class: e.class.name, cause: "unknown")
    end

    private

    def request(ipaddr: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = @uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      # Net::HTTP retries a timed-out GET once by default, doubling the
      # timeouts. failure_threshold already absorbs a one-off failure.
      http.max_retries = 0
      # ipaddr= dials the address but keeps the hostname for SNI and
      # certificate verification, so the check is as strict as the first.
      http.ipaddr = ipaddr if ipaddr

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
