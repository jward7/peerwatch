module Peerwatch
  # Decides, from this app's checks and the other observers' reports, when an
  # incident opens, who alerts, and when it resolves.
  #
  # reports: { observer_name => status payload Hash } for the observers that
  # answered this cycle.
  class Evaluator
    LOOKBACK = 20

    def initialize(reports:, now: Time.current, config: Peerwatch.config)
      @reports = reports.to_h.select { |_, report| report.is_a?(Hash) }
      @now = now
      @config = config
    end

    def call
      Peerwatch.quietly("evaluator") do
        next if @config.self_name.blank?

        live_names = Peer.live.pluck(:name)
        # A removed peer is no longer evaluated, so close anything it left open.
        Incident.open.where.not(peer_name: live_names).update_all(resolved_at: @now)
        Peer.live.where.not(name: @config.self_name).order(:name).each do |peer|
          Peerwatch.quietly("evaluate #{peer.name}") { evaluate(peer, live_names) }
        end
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
      if peer.contact_emails.any?
        AlertMailer.down(peer, incident, overrun: incident.planned).deliver_later
      end
      incident.update!(alerted_at: @now, alerted_by: @config.self_name)
    end

    def handle_recovery(peer, incident)
      incident.update!(resolved_at: @now)
      if incident.alerted_by == @config.self_name
        AlertMailer.recovered(peer, incident).deliver_later if peer.contact_emails.any?
        incident.update!(recovery_alerted_at: @now)
      end
      if incident.notified_at
        notify(:recovered, peer, AlertText.recovered_subject(peer, incident), AlertText.recovered_body(peer, incident))
      end
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
