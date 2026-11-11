module Peerwatch
  class Incident < ApplicationRecord
    scope :open, -> { where(resolved_at: nil) }
    scope :for_peer, ->(name) { where(peer_name: name) }

    def open?
      resolved_at.nil?
    end

    def alerted?
      alerted_at.present?
    end
  end
end
