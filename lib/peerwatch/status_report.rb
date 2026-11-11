module Peerwatch
  # What this app tells the others: its own view of every peer, its open
  # incidents, recently resolved incidents that were alerted, and whether it
  # can send mail.
  module StatusReport
    LOOKBACK = 20
    # How long a resolved, alerted incident stays in recent_incidents, so the
    # other apps can record who alerted even when the outage ended within a
    # cycle of the alert. Several probe cycles.
    RECENT_WINDOW = 15.minutes

    module_function

    def build
      config = Peerwatch.config
      {
        "name" => config.self_name,
        "version" => Peerwatch::VERSION,
        "generated_at" => Time.current.utc.iso8601,
        "can_email" => config.can_email ? true : false,
        "observations" => observations(config),
        # Open incidents only: observers read an alerted entry here as "this
        # outage is already being handled", so a resolved one must never be
        # listed here.
        "incidents" => Incident.open.order(:started_at).map { |incident| incident_row(incident) },
        # Kept apart from "incidents" for that reason; older versions ignore it.
        "recent_incidents" => recent_incidents.map do |incident|
          incident_row(incident).merge("resolved_at" => incident.resolved_at.utc.iso8601)
        end
      }
    end

    def recent_incidents(now = Time.current)
      Incident.where.not(alerted_at: nil).where(resolved_at: (now - RECENT_WINDOW)..).order(:resolved_at)
    end

    def incident_row(incident)
      {
        "peer" => incident.peer_name,
        "started_at" => incident.started_at.utc.iso8601,
        "planned" => incident.planned,
        "alerted_at" => incident.alerted_at&.utc&.iso8601,
        "alerted_by" => incident.alerted_by
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
