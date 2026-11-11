module Peerwatch
  # Uptime from this app's own checks. "up" and "maintenance" count as up; a
  # "down" check inside a planned incident is left out entirely, so declared
  # maintenance never lowers the figure.
  module Uptime
    module_function

    # A percentage (Float), or nil when there is nothing to count.
    def for(peer_name, since:)
      table([ peer_name ], { since => since })[peer_name][since]
    end

    # { peer_name => { label => percentage or nil } } for several peers and
    # windows, in a fixed number of queries however many peers there are.
    # sinces: { label => Time the window starts }.
    def table(peer_names, sinces)
      now = Time.current
      oldest = sinces.values.min
      in_range = Check.where(peer_name: peer_names, checked_at: oldest..)

      ups = sinces.transform_values do |since|
        in_range.where(checked_at: since..).where.not(state: "down").group(:peer_name).count
      end
      downs = in_range.where(state: "down").pluck(:peer_name, :checked_at).group_by(&:first)
      windows = Incident.where(peer_name: peer_names, planned: true)
                        .where("resolved_at IS NULL OR resolved_at >= ?", oldest)
                        .pluck(:peer_name, :started_at, :resolved_at)
                        .group_by(&:first)

      peer_names.index_with do |name|
        planned = Array(windows[name]).map { |_, started, resolved| started..(resolved || now) }
        counted_downs = Array(downs[name]).map(&:last).reject { |at| planned.any? { |w| w.cover?(at) } }

        sinces.to_h do |label, since|
          up = ups[label].fetch(name, 0)
          total = up + counted_downs.count { |at| at >= since }
          [ label, total.zero? ? nil : up * 100.0 / total ]
        end
      end
    end
  end
end
