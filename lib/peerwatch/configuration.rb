module Peerwatch
  class Configuration
    # This app's own name in the registry (must match its peer row).
    attr_reader :self_name
    # Shared secret every app in the mesh presents as a Bearer token. Blank
    # disables the API endpoints and all syncing.
    attr_accessor :token
    # One known peer's base URL, used to join the mesh before the registry
    # has synced. Optional once peers are known.
    attr_accessor :seed_url
    # The admin pages inherit this controller, so they get the host's
    # authentication, authorisation and layout.
    attr_accessor :admin_parent_controller
    attr_accessor :layout
    # The alert mailer inherits this, so it gets the host's From address,
    # interceptors and suppression rules.
    attr_accessor :mailer_parent
    # False for an app whose mail does not reach real inboxes (a staging app
    # with a mail catcher). It still observes and votes; it never sends.
    attr_accessor :can_email
    # Called once per incident event with a Hash: { event: :down | :recovered,
    # peer:, subject:, body: }. Wire it to the host's own alert channel.
    attr_accessor :notifier
    attr_accessor :queue_name
    attr_accessor :open_timeout, :read_timeout
    # Consecutive failed checks before a peer counts as down, and consecutive
    # good ones before it counts as recovered.
    attr_accessor :failure_threshold, :recovery_threshold
    # How long the elected sender has before another observer sends instead.
    attr_accessor :fallback_after
    attr_accessor :retention_days
    # Plain http peer URLs are refused unless this is true.
    attr_accessor :allow_http
    # Peerwatch refuses to connect to loopback, private, link-local and other
    # non-public addresses, and refuses peer rows that name one, unless this
    # is true (local testing only).
    attr_accessor :allow_private_addresses
    # nil means any. An Array of hostnames: a peer URL's host must be one of
    # them (case-insensitive, exact match).
    attr_accessor :allowed_peer_hosts
    # nil means any. An Array of domains: every contact email must be at one
    # of them (case-insensitive, exact match on the part after the @).
    attr_accessor :allowed_contact_domains

    def initialize
      @admin_parent_controller = "ApplicationController"
      @layout = "application"
      @mailer_parent = "ActionMailer::Base"
      @can_email = true
      @notifier = nil
      @queue_name = :default
      @open_timeout = 5
      @read_timeout = 5
      @failure_threshold = 2
      @recovery_threshold = 2
      @fallback_after = 8 * 60
      @retention_days = 30
      @allow_http = false
      @allow_private_addresses = false
      @allowed_peer_hosts = nil
      @allowed_contact_domains = nil
    end

    # Always a String (or nil): names are compared with registry rows and
    # with other apps' reports, so a Symbol here would never match.
    def self_name=(name)
      @self_name = name&.to_s
    end

    def user_agent
      "peerwatch/#{Peerwatch::VERSION}"
    end

    def api_enabled?
      token.to_s != ""
    end
  end
end
