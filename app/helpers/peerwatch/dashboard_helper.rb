module Peerwatch
  module DashboardHelper
    STATE_BADGES = {
      "up" => [ "text-bg-success", "up" ],
      "maintenance" => [ "text-bg-info", "maintenance" ],
      "down" => [ "text-bg-danger", "down" ],
      "none" => [ "text-bg-secondary", "no data" ]
    }.freeze

    def peerwatch_state_badge(state)
      return "—" if state == "self"

      css, label = STATE_BADGES.fetch(state, STATE_BADGES["none"])
      tag.span(label, class: "badge #{css}")
    end

    def peerwatch_uptime(value)
      value.nil? ? "—" : format("%.2f%%", value)
    end

    def peerwatch_time(time)
      time ? time.utc.strftime("%Y-%m-%d %H:%M UTC") : "—"
    end
  end
end
