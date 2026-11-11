module Peerwatch
  # Reads only the database and Rails.cache: no outbound calls at render.
  class DashboardController < AdminController
    def show
      @self_name = Peerwatch.config.self_name.to_s
      @peers = Peer.live.sort_by { |peer| [ peer.self? ? 0 : 1, peer.name ] }
      @observers = ([ @self_name ] + @peers.map(&:name)).reject(&:blank?).uniq
      @latest_checks = @peers.to_h { |peer| [ peer.name, Check.for_peer(peer.name).recent_first.first ] }
      @matrix = build_matrix
      @uptime = Uptime.table(@peers.map(&:name), { "24h" => 24.hours.ago, "7d" => 7.days.ago, "30d" => 30.days.ago })
      @open_incidents = Incident.open.order(started_at: :desc)
      @resolved_incidents = Incident.where.not(resolved_at: nil).order(resolved_at: :desc).limit(20)
    end

    private

    # { [peer_name, observer_name] => "up" | "maintenance" | "down" | "none" | "self" }
    def build_matrix
      observations = @observers.to_h { |observer| [ observer, observations_from(observer) ] }
      @peers.each_with_object({}) do |peer, matrix|
        @observers.each do |observer|
          matrix[[ peer.name, observer ]] =
            if observer == peer.name then "self"
            elsif observations[observer].nil? then "none"
            else observations[observer].fetch(peer.name, "none")
            end
        end
      end
    end

    # { peer_name => state } as this observer last saw it, or nil when there
    # is no usable report from it.
    def observations_from(observer)
      if observer == @self_name
        return @latest_checks.compact.transform_values(&:state)
      end

      report = Rails.cache.read("peerwatch/report/#{observer}")
      return nil unless report.is_a?(Hash) && report["kind"] == "ok" && report["body"].is_a?(Hash)

      Array(report["body"]["observations"]).each_with_object({}) do |o, states|
        states[o["peer"]] = o["state"] if o.is_a?(Hash) && Check::STATES.include?(o["state"])
      end
    end
  end
end
