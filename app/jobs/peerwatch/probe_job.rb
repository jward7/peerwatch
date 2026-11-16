module Peerwatch
  # Every two minutes: probe each peer, collect their reports, merge their
  # registries, evaluate incidents and prune old checks. Never raises.
  class ProbeJob < ActiveJob::Base
    # How long the notifier stays quiet about a peer it has already been told
    # is blocked. A peer still blocked after this is reported again.
    BLOCKED_REMINDER = 24.hours

    queue_as { Peerwatch.config.queue_name }

    def perform
      Peerwatch.quietly("probe job") { run }
    end

    private

    def run
      config = Peerwatch.config
      return if config.self_name.blank?

      peers, blocked = partitioned
      # Nobody this app may ask: it has not joined yet, or its rules now block
      # every row it holds. Peers are the usual source of registry rows, so
      # without them the seed URL is the only way a row (or its repair) can
      # still arrive.
      if peers.empty?
        Sync.pull
        peers, blocked = partitioned
      end
      log_blocked(blocked)
      notify_blocked(blocked, watching: peers.size)
      forget_blocked(peers)
      reports = {}
      kinds = {}
      peers.each do |peer|
        Peerwatch.quietly("probe #{peer.name}") do
          kinds[peer.name] = "unreachable"
          outcome = Probe.call(url: peer.health_url, ip: peer.ip)
          state = outcome.ok? ? "up" : "down"

          if outcome.ok? && config.api_enabled?
            reply = Client.new(peer.url).status
            if reply.kind == :maintenance
              state = "maintenance"
              kinds[peer.name] = "maintenance"
            elsif reply.kind == :ok && reply.body.is_a?(Hash)
              reports[peer.name] = reply.body
              kinds[peer.name] = "ok"
            end
          end

          Check.create!(peer_name: peer.name, checked_at: Time.current, state: state,
                        status_code: outcome.status_code, latency_ms: outcome.latency_ms,
                        error_class: outcome.error_class, cause: outcome.cause)
        end
      end

      Peerwatch.quietly("registry merge from reports") do
        urls = peers.index_by(&:name).transform_values(&:url)
        Sync.pull(reports.keys.map { |name| Client.new(urls[name]).registry })
      end

      Peerwatch.quietly("report cache") do
        fetched_at = Time.current.utc.iso8601
        kinds.each do |name, kind|
          Rails.cache.write("peerwatch/report/#{name}",
                            { "fetched_at" => fetched_at, "kind" => kind, "body" => reports[name] },
                            expires_in: 15.minutes)
        end
      end

      Evaluator.new(reports: reports).call

      Peerwatch.quietly("check pruning") do
        Check.where(checked_at: ...config.retention_days.days.ago).delete_all
      end
    end

    def others
      Peer.live.where.not(name: Peerwatch.config.self_name)
    end

    # [permitted, blocked] among the other live peers.
    def partitioned
      others.order(:name).to_a.partition(&:permitted?)
    end

    # A blocked peer is not probed, so no check fails and no incident opens:
    # without this the host hears nothing, however long it lasts. One call
    # per peer, then quiet for BLOCKED_REMINDER. The cache is the only memory
    # of having told the host, so a cache that keeps nothing gets no call
    # (the log line below still says so every run) rather than one a cycle.
    def notify_blocked(blocked, watching:)
      notifier = Peerwatch.config.notifier
      return if notifier.nil?

      blocked.each do |peer|
        Peerwatch.quietly("blocked notice #{peer.name}") do
          key = blocked_key(peer)
          next if Rails.cache.read(key)

          noticed_at = Time.current
          Rails.cache.write(key, noticed_at.utc.iso8601, expires_in: BLOCKED_REMINDER)
          next unless Rails.cache.read(key)

          notifier.call({ event: :blocked, peer: peer.name,
                          subject: AlertText.blocked_subject(peer, noticed_at),
                          body: AlertText.blocked_body(peer, watching: watching) })
        end
      end
    end

    # A peer that is permitted again is reported afresh if it is blocked again.
    def forget_blocked(peers)
      Peerwatch.quietly("blocked notice reset") do
        peers.each { |peer| Rails.cache.delete(blocked_key(peer)) }
      end
    end

    def blocked_key(peer)
      "peerwatch/blocked/#{peer.name}"
    end

    # One line per run, however many peers are blocked.
    def log_blocked(blocked)
      return if blocked.empty?

      Peerwatch.logger&.warn(
        "[Peerwatch] not probing #{blocked.size} peer(s) blocked by this app's rules: " +
          blocked.map { |peer| "#{peer.name} (#{peer.blocked_reasons.to_sentence})" }.join("; ")
      )
    end
  end
end
