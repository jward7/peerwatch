require "net/http"
require "uri"
require "json"

module Peerwatch
  # Talks to another app's Peerwatch endpoints. Never raises: every call
  # returns a Reply whose kind says what happened.
  class Client
    # kind: :ok (body is parsed JSON), :maintenance (the app answered 503),
    # :unreachable (anything else).
    Reply = Struct.new(:kind, :body, keyword_init: true) do
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
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      http.max_retries = 0 # keep the configured timeouts the real bound

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
    rescue StandardError
      Reply.new(kind: :unreachable)
    end
  end
end
