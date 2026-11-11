module Peerwatch
  # Decides, from this app's checks and the other observers' reports, when an
  # incident opens, who alerts, and when it resolves.
  #
  # reports: { observer_name => status payload Hash } for the observers that
  # answered this cycle.
  class Evaluator
    LOOKBACK = 20
    # Another app's alert belongs to one of this app's incidents when its
    # alerted_at falls within that incident, give or take this much: each app
    # timestamps an outage from its own checks, a cycle or two apart.
    ALERT_MATCH_SLACK = 5.minutes

    def initialize(reports:, now: Time.current, config: Peerwatch.config)
      @reports = reports.to_h.select { |_, report| report.is_a?(Hash) }
      @now = now
      @config = config
    end

    def call
      Peerwatch.quietly("evaluator") do
        next if @config.self_name.blank?

        live = Peer.live.order(:name).to_a
        # A removed peer is no longer evaluated, so close anything it left open.
        Incident.open.where.not(peer_name: live.map(&:name)).update_all(resolved_at: @now)
        # A peer this app's rules block is neither probed nor asked for a
        # report, so it is not evaluated, its contacts are never emailed, and
        # it is not counted as an observer whose agreement is awaited.
        permitted = live.select(&:permitted?)
        permitted_names = permitted.map(&:name)
        permitted.each do |peer|
          next if peer.name == @config.self_name

          Peerwatch.quietly("evaluate #{peer.name}") { evaluate(peer, permitted_names) }
        end
        Peerwatch.quietly("record alerts") { record_alerts_from_reports }
      end
    end

    private

    def evaluate(peer, live_names)
      limit = [ LOOKBACK, @config.failure_threshold, @config.recovery_threshold ].max
      checks = Check.for_peer(peer.name).recent_first.limit(limit).to_a
      incident = Incident.open.for_peer(peer.name).order(:started_at).last

      if Check.all_down?(checks, @config.failure_threshold)
        handle_down(peer, incident || open_incident(peer, checks), live_names)
      elsif incident && recovered?(checks)
        handle_recovery(peer, incident)
      end
    end

    def recovered?(checks)
      checks.size >= @config.recovery_threshold &&
        checks.first(@config.recovery_threshold).none?(&:down?)
    end

    def open_incident(peer, checks)
      Incident.create!(peer_name: peer.name,
                       started_at: checks.take_while(&:down?).last.checked_at,
                       planned: peer.in_maintenance?(@now))
    end

    def handle_down(peer, incident, live_names)
      # Declared maintenance: record it, tell nobody.
      if peer.in_maintenance?(@now)
        incident.update!(planned: true) unless incident.planned
        return
      end
      return if incident.alerted?

      others = live_names - [ @config.self_name, peer.name ]
      agreeing = @reports.slice(*others).select { |_, report| observation(report, peer.name)["down"] == true }
      if others.any? && agreeing.empty?
        Peerwatch.logger&.info("[Peerwatch] #{peer.name} looks down from here only; staying quiet")
        return
      end

      notify(:down, peer, AlertText.down_subject(peer, incident, overrun: incident.planned),
             AlertText.down_body(peer, incident, overrun: incident.planned)) if incident.notified_at.nil?
      incident.update!(notified_at: @now) if incident.notified_at.nil?

      if (theirs = already_alerted(agreeing.values, peer.name))
        alerted_at = ActiveModel::Type::DateTime.new.cast(theirs["alerted_at"]) || @now
        incident.update!(alerted_at: alerted_at, alerted_by: theirs["alerted_by"].to_s)
        return
      end

      send_down(peer, incident) if elected?(incident, peer, agreeing)
    end

    def elected?(incident, peer, agreeing)
      candidates = agreeing.select { |_, report| report["can_email"] == true }.keys
      candidates << @config.self_name if @config.can_email
      return true if candidates.min == @config.self_name

      # The elected sender has had its chance. A planned incident only became
      # alertable when its window ended, so the wait starts there.
      waiting_since = incident.started_at
      waiting_since = [ waiting_since, peer.maintenance_until ].max if incident.planned && peer.maintenance_until
      @config.can_email && @now - waiting_since > @config.fallback_after
    end

    def send_down(peer, incident)
      if peer.contact_emails.any? && peer.permitted?
        AlertMailer.down(peer, incident, overrun: incident.planned).deliver_later
      end
      incident.update!(alerted_at: @now, alerted_by: @config.self_name)
    end

    def handle_recovery(peer, incident)
      incident.update!(resolved_at: @now)
      if incident.alerted_by == @config.self_name
        AlertMailer.recovered(peer, incident).deliver_later if peer.contact_emails.any? && peer.permitted?
        incident.update!(recovery_alerted_at: @now)
      end
      if incident.notified_at
        notify(:recovered, peer, AlertText.recovered_subject(peer, incident), AlertText.recovered_body(peer, incident))
      end
    end

    # Every app probes on the same tick, so the report fetched in the cycle
    # the sender alerts usually predates its alert. When the outage then ends
    # within a cycle, handle_down never sees the alert and this app's incident
    # would say nobody alerted. Record it from the reports afterwards instead.
    # Resolved incidents only: an open one is left to handle_down, so this
    # never changes who is emailed.
    def record_alerts_from_reports
      window = StatusReport::RECENT_WINDOW + ALERT_MATCH_SLACK
      Incident.where(alerted_at: nil).where(resolved_at: (@now - window)..).find_each do |incident|
        theirs = alert_for(incident)
        next unless theirs

        incident.update!(alerted_at: theirs.first, alerted_by: theirs.last)
      end
    end

    # [alerted_at, alerted_by] from another app's report for the same outage.
    def alert_for(incident)
      from = incident.started_at - ALERT_MATCH_SLACK
      to = incident.resolved_at + ALERT_MATCH_SLACK
      @reports.each_value do |report|
        (Array(report["incidents"]) + Array(report["recent_incidents"])).each do |row|
          next unless row.is_a?(Hash) && row["peer"] == incident.peer_name
          # This app did not alert (its incident would say so), whatever a
          # report claims.
          next if row["alerted_by"].blank? || row["alerted_by"].to_s == @config.self_name

          at = ActiveModel::Type::DateTime.new.cast(row["alerted_at"])
          return [ at, row["alerted_by"].to_s ] if at && at.between?(from, to)
        end
      end
      nil
    end

    def notify(event, peer, subject, body)
      return unless @config.notifier

      Peerwatch.quietly("notifier") do
        @config.notifier.call({ event: event, peer: peer.name, subject: subject, body: body })
      end
    end

    def observation(report, peer_name)
      Array(report["observations"]).find { |o| o.is_a?(Hash) && o["peer"] == peer_name } || {}
    end

    def already_alerted(reports, peer_name)
      reports.each do |report|
        found = Array(report["incidents"]).find do |i|
          i.is_a?(Hash) && i["peer"] == peer_name && i["alerted_at"].present?
        end
        return found if found
      end
      nil
    end
  end
end
