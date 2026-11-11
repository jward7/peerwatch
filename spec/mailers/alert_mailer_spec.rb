RSpec.describe Peerwatch::AlertMailer do
  let(:peer) { create_peer("bravo", contact_emails: [ "ops@example.com" ], maintenance_note: "db upgrade") }
  let(:incident) do
    Peerwatch::Incident.create!(peer_name: "bravo", started_at: Time.utc(2026, 1, 5, 3, 12),
                                resolved_at: Time.utc(2026, 1, 5, 3, 40))
  end

  it "inherits the host mailer, so its From address applies" do
    mail = described_class.down(peer, incident)

    expect(described_class.superclass).to eq(ApplicationMailer)
    expect(mail.from).to eq([ "peerwatch@alpha.example" ])
    expect(mail.to).to eq([ "ops@example.com" ])
    expect(mail.content_type).to start_with("text/plain")
    expect(mail.body.to_s).to include("Peer: bravo", "Down since: 2026-01-05 03:12 UTC")
  end

  it "words an overrun" do
    mail = described_class.down(peer, incident, overrun: true)

    expect(mail.subject).to eq("Peerwatch: bravo is still down after its maintenance window (since 2026-01-05 03:12 UTC)")
    expect(mail.body.to_s).to include("Maintenance note: db upgrade")
  end

  it "sends recovery" do
    mail = described_class.recovered(peer, incident)

    expect(mail.subject).to eq("Peerwatch: bravo recovered (down since 2026-01-05 03:12 UTC)")
    expect(mail.body.to_s).to include("Recovered at: 2026-01-05 03:40 UTC")
  end
end
