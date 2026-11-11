module Peerwatch
  # Moves registry rows between apps: a pull from every known peer each
  # probe cycle (the repair path) and a push to every peer on each save (so a
  # maintenance declaration arrives before the app goes down).
  module Sync
    module_function

    def sources
      urls = Peer.live.where.not(name: Peerwatch.config.self_name.to_s).pluck(:url)
      urls << Peerwatch.config.seed_url if Peerwatch.config.seed_url.present?
      urls.map { |url| url.to_s.chomp("/") }.uniq
    end

    # Returns the number of rows applied. Pass replies already fetched with
    # Client#registry to avoid fetching them again.
    def pull(replies = nil)
      return 0 unless Peerwatch.config.api_enabled?

      Peerwatch.quietly("registry pull") do
        replies ||= sources.map { |url| Client.new(url).registry }
        replies.sum do |reply|
          reply.ok? && reply.body.is_a?(Hash) ? RegistryMerge.call(reply.body["peers"]) : 0
        end
      end || 0
    end

    # Returns how many peers accepted the row.
    def push(peer)
      return 0 unless Peerwatch.config.api_enabled?

      Peerwatch.quietly("registry push #{peer&.name}") do
        row = peer.registry_row
        Peer.live.where.not(name: Peerwatch.config.self_name.to_s).count do |target|
          Client.new(target.url).push_registry([ row ]).ok?
        end
      end || 0
    end
  end
end
