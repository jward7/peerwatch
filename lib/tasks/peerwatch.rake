namespace :peerwatch do
  desc "Declare a maintenance window for this app and push it to every peer now. " \
       "MINUTES=30 NOTE=\"db upgrade\"; MINUTES=0 clears the window."
  task maintenance: :environment do
    self_name = Peerwatch.config.self_name.to_s
    abort "Peerwatch: config.self_name is not set, so this app has no peer row to update." if self_name.empty?

    peer = Peerwatch::Peer.live.find_by(name: self_name)
    abort "Peerwatch: no peer row named #{self_name.inspect}. Add this app on the peers page first." unless peer

    minutes = Integer(ENV.fetch("MINUTES", ""), exception: false)
    abort "Peerwatch: MINUTES must be a whole number (0 clears the window)." if minutes.nil? || minutes.negative?

    if minutes.zero?
      peer.maintenance_until = nil
      peer.maintenance_note = nil
    else
      peer.maintenance_until = minutes.minutes.from_now
      peer.maintenance_note = ENV["NOTE"].presence
    end
    abort "Peerwatch: could not save: #{peer.errors.full_messages.to_sentence}" unless peer.save

    # Synchronous on purpose: this app may be about to go down.
    accepted = Peerwatch::Sync.push(peer)
    targets = Peerwatch::Sync.targets.size # peers this app's rules block are never pushed to
    window = minutes.zero? ? "cleared" : "until #{peer.maintenance_until.utc.strftime("%Y-%m-%d %H:%M UTC")}"
    puts "Peerwatch: maintenance #{window}; #{accepted} of #{targets} peers accepted it."
  end
end
