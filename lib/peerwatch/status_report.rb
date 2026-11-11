module Peerwatch
  # What this app tells the others: its own view of every peer, its open
  # incidents, and whether it can send mail.
  module StatusReport
    LOOKBACK = 20

    module_function

    def build
      config = Peerwatch.config
      {
        "name" => config.self_name,
        "version" => Peerwatch::VERSION,
        "generated_at" => Time.current.utc.iso8601,
        "can_email" => config.can_email ? true : false,
        "observations" => observations(config),
        "incidents" => Incident.open.order(:started_at).map do |incident|
          {
            "peer" => incident.peer_name,
            "started_at" => incident.started_at.utc.iso8601,
            "planned" => incident.planned,
            "alerted_at" => incident.alerted_at&.utc&.iso8601,
            "alerted_by" => incident.alerted_by
          }
        end
      }
    end

    def observations(config)
      Peer.live.where.not(name: config.self_name.to_s).order(:name).filter_map do |peer|
        # A blocked peer is no longer probed, so its last checks are stale
        # and must not count towards another app's quorum.
        next unless peer.permitted?

        checks = Check.for_peer(peer.name).recent_first.limit([ LOOKBACK, config.failure_threshold ].max).to_a
        latest = checks.first
        next unless latest

        {
          "peer" => peer.name,
          "state" => latest.state,
          "down" => Check.all_down?(checks, config.failure_threshold),
          "consecutive_failures" => checks.take_while(&:down?).size,
          "checked_at" => latest.checked_at.utc.iso8601,
          "latency_ms" => latest.latency_ms,
          "cause" => latest.cause
        }
      end
    end
  end
end
