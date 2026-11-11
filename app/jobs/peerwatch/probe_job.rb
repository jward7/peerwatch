module Peerwatch
  # Every two minutes: probe each peer, collect their reports, merge their
  # registries, evaluate incidents and prune old checks. Never raises.
  class ProbeJob < ActiveJob::Base
    queue_as { Peerwatch.config.queue_name }

    def perform
      Peerwatch.quietly("probe job") { run }
    end

    private

    def run
      config = Peerwatch.config
      return if config.self_name.blank?

      # Joining via the seed URL: nothing to probe until the registry arrives.
      Sync.pull if others.none?

      peers = others.order(:name).to_a
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
  end
end
