module Peerwatch
  # Pushes one registry row to every peer after an admin edit. Best-effort:
  # the next probe cycle's pull repairs anything this misses.
  class PushJob < ActiveJob::Base
    queue_as { Peerwatch.config.queue_name }

    def perform(peer_name)
      Peerwatch.quietly("push job") do
        peer = Peer.find_by(name: peer_name)
        Sync.push(peer) if peer
      end
    end
  end
end
