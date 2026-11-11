RSpec.describe Peerwatch::Uptime do
  it "is nil with no checks" do
    expect(described_class.for("bravo", since: 1.day.ago)).to be_nil
  end

  it "counts up and maintenance as up" do
    add_check("bravo", "up", at: 3.hours.ago)
    add_check("bravo", "maintenance", at: 2.hours.ago)
    add_check("bravo", "down", at: 1.hour.ago)
    add_check("bravo", "down", at: 3.days.ago)

    expect(described_class.for("bravo", since: 1.day.ago)).to be_within(0.001).of(200.0 / 3)
  end

  it "excludes down checks inside a planned incident" do
    add_check("bravo", "up", at: 5.hours.ago)
    add_check("bravo", "down", at: 3.hours.ago)
    add_check("bravo", "down", at: 2.hours.ago)
    add_check("bravo", "down", at: 30.minutes.ago)
    Peerwatch::Incident.create!(peer_name: "bravo", started_at: 3.hours.ago - 1.minute,
                                resolved_at: 1.hour.ago, planned: true)

    expect(described_class.for("bravo", since: 1.day.ago)).to eq(50.0)
  end

  it "is nil when every check falls in a planned incident" do
    add_check("bravo", "down", at: 10.minutes.ago)
    Peerwatch::Incident.create!(peer_name: "bravo", started_at: 1.hour.ago, planned: true)

    expect(described_class.for("bravo", since: 1.day.ago)).to be_nil
  end

  it "computes several peers and windows at once, matching .for" do
    freeze_time do
      add_check("bravo", "up", at: 2.hours.ago)
      add_check("bravo", "down", at: 1.hour.ago)
      add_check("bravo", "down", at: 3.days.ago)
      add_check("bravo", "up", at: 20.days.ago)
      add_check("charlie", "down", at: 5.days.ago)
      Peerwatch::Incident.create!(peer_name: "charlie", started_at: 6.days.ago, resolved_at: 4.days.ago, planned: true)
      add_check("charlie", "up", at: 1.hour.ago)
      sinces = { "24h" => 24.hours.ago, "7d" => 7.days.ago, "30d" => 30.days.ago }

      table = described_class.table(%w[bravo charlie delta], sinces)

      expect(table["bravo"]).to eq("24h" => 50.0, "7d" => 100.0 / 3, "30d" => 50.0)
      expect(table["charlie"]).to eq("24h" => 100.0, "7d" => 100.0, "30d" => 100.0)
      expect(table["delta"]).to eq("24h" => nil, "7d" => nil, "30d" => nil)
      %w[bravo charlie delta].each do |name|
        sinces.each { |label, since| expect(table[name][label]).to eq(described_class.for(name, since: since)) }
      end
    end
  end
end
