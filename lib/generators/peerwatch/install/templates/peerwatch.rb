Peerwatch.configure do |config|
  # This app's name in the registry. It must match this app's row on the
  # peers page, and it is how the app recognises itself in synced data.
  config.self_name = "alpha"

  # The secret every app in the mesh shares, sent as a Bearer token. Anyone
  # holding it can read and edit the registry. Blank disables the API
  # endpoints and all syncing (probing still runs).
  config.token = Rails.application.credentials.dig(:peerwatch, :token)

  # One known peer's base URL, used to join the mesh before the registry
  # has synced. Optional once peers are known.
  # config.seed_url = "https://bravo.example"

  # The admin pages inherit this controller (for your authentication and
  # authorisation) and render inside this layout. They are only as private as
  # this controller: the default is usually not admin-only, so change it.
  # config.admin_parent_controller = "ApplicationController"
  # config.layout = "application"

  # The alert mailer inherits this, so your From address and interceptors apply.
  # config.mailer_parent = "ActionMailer::Base"

  # False when this app's mail reaches nobody (a staging mail catcher). It
  # still observes and votes, but never sends alert mail.
  # config.can_email = true

  # Called once per incident event with
  # { event: :down | :recovered, peer:, subject:, body: }.
  # Wire it to your own alert channel. Errors it raises are logged and ignored.
  # config.notifier = ->(event) { Rails.logger.warn(event[:subject]) }

  # The queue both Peerwatch jobs run on.
  # config.queue_name = :default

  # Seconds to wait to connect to, and then hear back from, a peer.
  # config.open_timeout = 5
  # config.read_timeout = 5

  # Consecutive failed checks before a peer counts as down, and consecutive
  # good ones before it counts as recovered.
  # config.failure_threshold = 2
  # config.recovery_threshold = 2

  # Seconds the elected sender has to send the alert before another
  # observer that can email sends it instead.
  # config.fallback_after = 8 * 60

  # Days of checks to keep.
  # config.retention_days = 30

  # Plain http peer URLs are refused unless this is true (local testing only).
  # config.allow_http = Rails.env.development?

  # Peerwatch never connects to a loopback, private, link-local or other
  # non-public address, and refuses peer rows that name one, unless this is
  # true (local testing against localhost only).
  # config.allow_private_addresses = false

  # Registry rows come from whoever holds the token. These limit what such a
  # row can make this app do; nil means any. Set both in production.
  # A peer URL's host must be one of these hostnames (exact, case-insensitive):
  # config.allowed_peer_hosts = nil # e.g. %w[alpha.example bravo.example]
  # Every contact email must be at one of these domains (exact, case-insensitive):
  # config.allowed_contact_domains = nil # e.g. %w[example.com]
end
