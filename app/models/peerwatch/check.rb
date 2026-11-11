module Peerwatch
  class Check < ApplicationRecord
    STATES = %w[up maintenance down].freeze

    validates :peer_name, :checked_at, presence: true
    validates :state, inclusion: { in: STATES }

    scope :for_peer, ->(name) { where(peer_name: name) }
    scope :recent_first, -> { order(checked_at: :desc, id: :desc) }

    # True when the latest `count` checks (newest first) all exist and are all down.
    def self.all_down?(checks, count)
      checks.size >= count && checks.first(count).all?(&:down?)
    end

    def down?
      state == "down"
    end
  end
end
