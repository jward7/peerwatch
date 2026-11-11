module PeerwatchHelpers
  # What every name resolves to in the specs unless resolve_to says otherwise.
  DEFAULT_ADDRESS = "192.0.2.1".freeze

  # Make one hostname resolve to these addresses, at the one resolver seam.
  def resolve_to(host, *addresses)
    allow(Peerwatch::Address).to receive(:resolve).with(host).and_return(addresses)
  end

  def create_peer(name, **attrs)
    Peerwatch::Peer.create!({ name: name, url: "https://#{name}.example" }.merge(attrs))
  end

  def add_check(peer_name, state, at: Time.current, **attrs)
    Peerwatch::Check.create!({ peer_name: peer_name, state: state, checked_at: at,
                               cause: state == "down" ? "app" : nil }.merge(attrs))
  end

  # A status payload as another observer would send it.
  def report(name, can_email: true, observations: {}, incidents: [])
    {
      "name" => name,
      "can_email" => can_email,
      "observations" => observations.map { |peer, down| { "peer" => peer, "state" => down ? "down" : "up", "down" => down } },
      "incidents" => incidents
    }
  end
end
