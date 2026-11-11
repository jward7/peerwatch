require "net/http"
require "uri"
require "json"
require "peerwatch/address"

module Peerwatch
  # Talks to another app's Peerwatch endpoints. Never raises: every call
  # returns a Reply whose kind says what happened.
  #
  # The base URL comes from the registry or seed_url, and these requests
  # carry the token, so each one goes through Address first: a name that
  # resolves to a non-public address is refused without a request, and the
  # connection is pinned to the address that was checked. Redirects are never
  # followed.
  class Client
    # kind: :ok (body is parsed JSON), :maintenance (the app answered 503),
    # :unreachable (anything else). error_class names the exception behind an
    # :unreachable reply, if there was one ("Peerwatch::Address::NotPublic"
    # when the address was refused).
    Reply = Struct.new(:kind, :body, :error_class, keyword_init: true) do
      def ok? = kind == :ok
    end

    def initialize(base_url, config: Peerwatch.config)
      @base = base_url.to_s.chomp("/")
      @config = config
    end

    def status = get("/peerwatch/status")

    def registry = get("/peerwatch/registry")

    def push_registry(rows)
      perform(Net::HTTP::Post, "/peerwatch/registry") do |req|
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(peers: rows)
      end
    end

    private

    def get(path) = perform(Net::HTTP::Get, path)

    def perform(verb, path)
      uri = URI.parse(@base + path)
      dial = Address.dial_address(uri.hostname, config: @config)
      # No proxy (nil): a proxy would resolve the name itself, and the pin
      # below would not hold.
      http = Net::HTTP.new(uri.hostname, uri.port, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      http.max_retries = 0 # keep the configured timeouts the real bound
      http.ipaddr = dial if dial

      request = verb.new(uri.request_uri)
      request["User-Agent"] = @config.user_agent
      request["Authorization"] = "Bearer #{@config.token}"
      request["Accept"] = "application/json"
      yield request if block_given?

      response = http.request(request)
      case response.code.to_i
      when 200..299 then Reply.new(kind: :ok, body: JSON.parse(response.body.to_s.empty? ? "{}" : response.body))
      when 503 then Reply.new(kind: :maintenance)
      else Reply.new(kind: :unreachable)
      end
    rescue StandardError => e
      Reply.new(kind: :unreachable, error_class: e.class.name)
    end
  end
end
