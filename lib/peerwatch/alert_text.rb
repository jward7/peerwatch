module Peerwatch
  # The one home for alert wording, shared by the mailer and the notifier.
  # Every subject carries the peer name and the incident start, because
  # hosts may dedupe alerts on the exact subject.
  module AlertText
    CAUSES = {
      "app" => "app (the app did not answer its health URL)",
      "dns" => "dns (the name failed but the stored IP address answered)",
      "unknown" => "unknown (the request failed before any answer)"
    }.freeze

    module_function

    def down_subject(peer, incident, overrun: false)
      if overrun
        "Peerwatch: #{peer.name} is still down after its maintenance window (since #{stamp(incident.started_at)})"
      else
        "Peerwatch: #{peer.name} is down (since #{stamp(incident.started_at)})"
      end
    end

    def recovered_subject(peer, incident)
      "Peerwatch: #{peer.name} recovered (down since #{stamp(incident.started_at)})"
    end

    def down_body(peer, incident, overrun: false)
      cause = Check.for_peer(peer.name).recent_first.first&.cause || "unknown"
      lines = [
        "Peer: #{peer.name}",
        "URL: #{peer.health_url}",
        "Down since: #{stamp(incident.started_at)}",
        "Cause seen by #{Peerwatch.config.self_name}: #{CAUSES.fetch(cause, cause)}",
        "Observers agreeing: #{agreeing_observers(peer).join(", ")}"
      ]
      if overrun
        lines << "Maintenance window ended: #{peer.maintenance_until ? stamp(peer.maintenance_until) : "(cleared)"}"
        lines << "Maintenance note: #{peer.maintenance_note.presence || "(none)"}"
      end
      lines.join("\n")
    end

    def recovered_body(peer, incident)
      [
        "Peer: #{peer.name}",
        "URL: #{peer.health_url}",
        "Down since: #{stamp(incident.started_at)}",
        "Recovered at: #{stamp(incident.resolved_at || Time.current)}"
      ].join("\n")
    end

    def stamp(time)
      time.utc.strftime("%Y-%m-%d %H:%M UTC")
    end

    # This app plus every observer whose cached report says the peer is down.
    def agreeing_observers(peer)
      others = Peer.live.where.not(name: [ Peerwatch.config.self_name.to_s, peer.name ]).pluck(:name)
      agreeing = others.select do |observer|
        report = Rails.cache.read("peerwatch/report/#{observer}")
        observations = report.is_a?(Hash) && report["body"].is_a?(Hash) ? Array(report["body"]["observations"]) : []
        observations.any? { |o| o.is_a?(Hash) && o["peer"] == peer.name && o["down"] == true }
      end
      ([ Peerwatch.config.self_name.to_s ] + agreeing.sort).reject(&:blank?)
    end
  end
end
