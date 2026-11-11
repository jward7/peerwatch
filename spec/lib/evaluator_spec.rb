RSpec.describe Peerwatch::Evaluator do
  let(:now) { Time.utc(2026, 1, 5, 3, 16) }
  let(:events) { [] }

  before do
    travel_to(now)
    Peerwatch.config.notifier = ->(event) { events << event }
    create_peer("alpha")
    create_peer("bravo", contact_emails: [ "ops@example.com" ])
    create_peer("charlie")
  end

  after { travel_back }

  def down_checks(name, count, last_at: now)
    count.times { |i| add_check(name, "down", at: last_at - (count - 1 - i) * 2.minutes) }
  end

  def evaluate(reports = {}, at: now)
    perform_enqueued_jobs { described_class.new(reports: reports, now: at).call }
  end

  def agreeing(name = "charlie", **opts)
    { name => report(name, observations: { "bravo" => true }, **opts) }
  end

  def incident
    Peerwatch::Incident.for_peer("bravo").order(:id).last
  end

  def mails
    ActionMailer::Base.deliveries
  end

  it "needs failure_threshold consecutive failures" do
    add_check("bravo", "down", at: now - 4.minutes)
    add_check("bravo", "up", at: now - 2.minutes)
    add_check("bravo", "down", at: now)
    evaluate(agreeing)
    expect(Peerwatch::Incident.count).to eq(0)

    add_check("bravo", "down", at: now + 1.second)
    evaluate(agreeing)
    expect(incident).to have_attributes(started_at: now, planned: false)
  end

  it "starts the incident at the first check of the unbroken down run" do
    add_check("bravo", "up", at: now - 8.minutes)
    down_checks("bravo", 3)

    evaluate(agreeing)

    expect(incident.started_at).to eq(now - 4.minutes)
  end

  context "when another observer agrees" do
    it "notifies, mails and stamps the alert" do
      down_checks("bravo", 2)

      evaluate(agreeing)

      expect(incident).to have_attributes(alerted_by: "alpha", alerted_at: now, notified_at: now)
      expect(mails.size).to eq(1)
      expect(mails.first.to).to eq([ "ops@example.com" ])
      expect(mails.first.subject).to eq("Peerwatch: bravo is down (since 2026-01-05 03:14 UTC)")
      expect(events).to eq([ { event: :down, peer: "bravo", subject: mails.first.subject, body: events.first[:body] } ])
      expect(events.first[:body]).to include("Peer: bravo", "https://bravo.example/up", "Cause seen by alpha: app")
    end
  end

  it "stays quiet when the other observers say the peer is up" do
    down_checks("bravo", 2)

    evaluate({ "charlie" => report("charlie", observations: { "bravo" => false }) })

    expect(incident).to have_attributes(alerted_at: nil, notified_at: nil)
    expect(mails).to be_empty
    expect(events).to be_empty
  end

  it "stays quiet when no other observer answered (this app may be the isolated one)" do
    down_checks("bravo", 2)

    evaluate({})

    expect(incident.alerted_at).to be_nil
    expect(events).to be_empty
    expect(mails).to be_empty
  end

  it "ignores a report from an app that is not a live peer" do
    down_checks("bravo", 2)

    evaluate(agreeing("zulu"))

    expect(incident.alerted_at).to be_nil
  end

  it "alerts alone in a two-app mesh" do
    Peerwatch::Peer.find_by!(name: "charlie").remove!
    down_checks("bravo", 2)

    evaluate({})

    expect(incident.alerted_by).to eq("alpha")
    expect(mails.size).to eq(1)
    expect(events.size).to eq(1)
  end

  describe "sender election" do
    before do
      Peerwatch.config.self_name = "charlie"
      down_checks("bravo", 2)
    end

    it "leaves the alert to the first agreeing observer by name" do
      evaluate(agreeing("alpha"))

      expect(incident.alerted_at).to be_nil
      expect(mails).to be_empty
      expect(events.size).to eq(1) # every observer still tells its own host
    end

    it "skips an observer that cannot email" do
      evaluate(agreeing("alpha", can_email: false))

      expect(incident.alerted_by).to eq("charlie")
      expect(mails.size).to eq(1)
    end

    it "sends anyway once the elected sender has had fallback_after" do
      evaluate(agreeing("alpha"))
      expect(mails).to be_empty

      evaluate(agreeing("alpha"), at: incident.started_at + Peerwatch.config.fallback_after + 1)

      expect(incident.alerted_by).to eq("charlie")
      expect(mails.size).to eq(1)
      expect(events.size).to eq(1)
    end

    it "copies another observer's alert and sends nothing" do
      alerted_at = now - 1.minute
      incidents = [ { "peer" => "bravo", "started_at" => (now - 2.minutes).iso8601, "planned" => false,
                      "alerted_at" => alerted_at.iso8601, "alerted_by" => "alpha" } ]

      evaluate(agreeing("alpha", incidents: incidents), at: now + 1.hour)

      expect(incident).to have_attributes(alerted_by: "alpha", alerted_at: alerted_at)
      expect(mails).to be_empty
    end
  end

  it "never mails when this app cannot email, but still notifies" do
    Peerwatch.config.can_email = false
    down_checks("bravo", 2)

    evaluate(agreeing)
    evaluate(agreeing, at: now + 1.hour)

    expect(incident.alerted_at).to be_nil
    expect(mails).to be_empty
    expect(events.map { |e| e[:event] }).to eq([ :down ])
  end

  it "stamps the alert even when the peer has no contacts" do
    Peerwatch::Peer.find_by!(name: "bravo").update!(contact_emails: [])
    down_checks("bravo", 2)

    evaluate(agreeing)

    expect(incident.alerted_by).to eq("alpha")
    expect(mails).to be_empty
  end

  describe "a declared maintenance window" do
    before do
      Peerwatch::Peer.find_by!(name: "bravo").update!(maintenance_until: now + 30.minutes, maintenance_note: "db upgrade")
      down_checks("bravo", 2)
    end

    it "records a planned incident and tells nobody" do
      evaluate(agreeing)

      expect(incident).to have_attributes(planned: true, notified_at: nil, alerted_at: nil)
      expect(events).to be_empty
      expect(mails).to be_empty
    end

    it "alerts once, worded as an overrun, if the peer is still down when the window ends" do
      evaluate(agreeing)
      after_window = now + 31.minutes
      down_checks("bravo", 2, last_at: after_window)

      evaluate(agreeing, at: after_window)
      evaluate(agreeing, at: after_window + 2.minutes)

      expect(mails.size).to eq(1)
      expect(mails.first.subject).to eq("Peerwatch: bravo is still down after its maintenance window (since 2026-01-05 03:14 UTC)")
      expect(mails.first.body.to_s).to include("Maintenance note: db upgrade")
      expect(events.map { |e| e[:event] }).to eq([ :down ])
      expect(events.first[:subject]).to eq(mails.first.subject)
    end

    it "does not let every observer send at once when the window ends" do
      Peerwatch.config.self_name = "charlie"
      evaluate(agreeing("alpha"))
      after_window = now + 31.minutes
      down_checks("bravo", 2, last_at: after_window)

      evaluate(agreeing("alpha"), at: after_window)

      expect(mails).to be_empty
    end

    it "resolves silently if the peer recovers inside the window" do
      evaluate(agreeing)
      add_check("bravo", "up", at: now + 2.minutes)
      add_check("bravo", "up", at: now + 4.minutes)

      evaluate(agreeing, at: now + 4.minutes)

      expect(incident.resolved_at).to eq(now + 4.minutes)
      expect(events).to be_empty
      expect(mails).to be_empty
    end
  end

  describe "recovery" do
    it "needs recovery_threshold good checks, then mails from the alerter and notifies" do
      down_checks("bravo", 2)
      evaluate(agreeing)
      add_check("bravo", "up", at: now + 2.minutes)
      evaluate(agreeing, at: now + 2.minutes)
      expect(incident.resolved_at).to be_nil

      add_check("bravo", "maintenance", at: now + 4.minutes)
      evaluate(agreeing, at: now + 4.minutes)

      expect(incident).to have_attributes(resolved_at: now + 4.minutes, recovery_alerted_at: now + 4.minutes)
      expect(mails.map(&:subject)).to eq([
        "Peerwatch: bravo is down (since 2026-01-05 03:14 UTC)",
        "Peerwatch: bravo recovered (down since 2026-01-05 03:14 UTC)"
      ])
      expect(events.map { |e| e[:event] }).to eq([ :down, :recovered ])
    end

    it "sends no recovery mail when another observer alerted" do
      down_checks("bravo", 2)
      Peerwatch::Incident.create!(peer_name: "bravo", started_at: now - 2.minutes, notified_at: now,
                                  alerted_at: now, alerted_by: "charlie")
      add_check("bravo", "up", at: now + 2.minutes)
      add_check("bravo", "up", at: now + 4.minutes)

      evaluate(agreeing, at: now + 4.minutes)

      expect(incident.resolved_at).to be_present
      expect(incident.recovery_alerted_at).to be_nil
      expect(mails).to be_empty
      expect(events.map { |e| e[:event] }).to eq([ :recovered ])
    end
  end

  it "calls the notifier exactly once per event" do
    down_checks("bravo", 2)
    3.times { |i| evaluate(agreeing, at: now + i.minutes) }
    add_check("bravo", "up", at: now + 4.minutes)
    add_check("bravo", "up", at: now + 6.minutes)
    2.times { |i| evaluate(agreeing, at: now + (6 + i).minutes) }

    expect(events.map { |e| e[:event] }).to eq([ :down, :recovered ])
    expect(mails.size).to eq(2)
  end

  it "carries on when the notifier raises" do
    Peerwatch.config.notifier = ->(_event) { raise "notifier is broken" }
    down_checks("bravo", 2)

    expect { evaluate(agreeing) }.not_to raise_error

    expect(incident).to have_attributes(alerted_by: "alpha", notified_at: now)
    expect(mails.size).to eq(1)
  end

  it "never raises out of call" do
    allow(Peerwatch::Peer).to receive(:live).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect { evaluate(agreeing) }.not_to raise_error
  end

  it "does nothing without a self_name" do
    Peerwatch.config.self_name = nil
    down_checks("bravo", 2)

    evaluate(agreeing)

    expect(Peerwatch::Incident.count).to eq(0)
  end
end

RSpec.describe Peerwatch::Evaluator, "removed peers" do
  it "closes an open incident left behind by a removed peer, without alerting" do
    create_peer("alpha")
    create_peer("bravo").remove!
    incident = Peerwatch::Incident.create!(peer_name: "bravo", started_at: 10.minutes.ago)

    described_class.new(reports: {}).call

    expect(incident.reload.resolved_at).to be_present
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
