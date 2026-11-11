RSpec.describe Peerwatch::StatusReport do
  before do
    create_peer("alpha")
    create_peer("bravo")
    create_peer("charlie")
    create_peer("delta")
  end

  it "reports this app's view of every peer and its open incidents" do
    add_check("bravo", "up", at: 6.minutes.ago)
    add_check("bravo", "down", at: 4.minutes.ago, latency_ms: 120)
    add_check("bravo", "down", at: 2.minutes.ago, latency_ms: 130)
    add_check("charlie", "down", at: 2.minutes.ago)
    Peerwatch::Incident.create!(peer_name: "bravo", started_at: 4.minutes.ago)
    Peerwatch::Incident.create!(peer_name: "charlie", started_at: 1.day.ago, resolved_at: 1.hour.ago)

    report = described_class.build

    expect(report).to include("name" => "alpha", "version" => Peerwatch::VERSION, "can_email" => true)
    bravo, charlie = report["observations"]
    expect(bravo).to include("peer" => "bravo", "state" => "down", "down" => true,
                             "consecutive_failures" => 2, "latency_ms" => 130, "cause" => "app")
    expect(charlie).to include("peer" => "charlie", "down" => false, "consecutive_failures" => 1)
    expect(report["observations"].size).to eq(2)
    expect(report["incidents"]).to contain_exactly(
      hash_including("peer" => "bravo", "planned" => false, "alerted_at" => nil, "alerted_by" => nil)
    )
  end

  it "lists recently resolved, alerted incidents apart from the open ones" do
    freeze_time do
      Peerwatch::Incident.create!(peer_name: "bravo", started_at: 20.minutes.ago, resolved_at: 4.minutes.ago,
                                  alerted_at: 16.minutes.ago, alerted_by: "alpha")
      Peerwatch::Incident.create!(peer_name: "charlie", started_at: 10.minutes.ago, resolved_at: 2.minutes.ago)
      Peerwatch::Incident.create!(peer_name: "delta", started_at: 2.hours.ago, resolved_at: 1.hour.ago,
                                  alerted_at: 2.hours.ago, alerted_by: "alpha")

      report = described_class.build

      expect(report["incidents"]).to be_empty
      expect(report["recent_incidents"]).to contain_exactly(
        hash_including("peer" => "bravo", "alerted_by" => "alpha", "alerted_at" => 16.minutes.ago.utc.iso8601,
                       "resolved_at" => 4.minutes.ago.utc.iso8601)
      )
    end
  end

  it "says when this app cannot email" do
    Peerwatch.config.can_email = false

    expect(described_class.build["can_email"]).to be(false)
  end
end

RSpec.describe Peerwatch::Configuration do
  it "stores self_name as a String, so a Symbol still matches registry rows" do
    config = described_class.new
    config.self_name = :alpha

    expect(config.self_name).to eq("alpha")
  end
end
