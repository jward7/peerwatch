RSpec.describe Peerwatch::ProbeJob do
  let(:bravo_report) do
    report("bravo", observations: { "delta" => true }).merge("generated_at" => Time.current.iso8601)
  end
  let(:echo_row) do
    { "name" => "echo", "url" => "https://echo.example", "health_path" => "/up",
      "contact_emails" => [], "revision_at" => Time.current.iso8601(6) }
  end

  before do
    create_peer("alpha")
    create_peer("bravo")
    create_peer("charlie")
    create_peer("delta")

    stub_request(:get, "https://bravo.example/up").to_return(status: 200)
    stub_request(:get, "https://bravo.example/peerwatch/status").to_return(status: 200, body: bravo_report.to_json)
    stub_request(:get, "https://bravo.example/peerwatch/registry")
      .to_return(status: 200, body: { peers: [ echo_row ] }.to_json)
    stub_request(:get, "https://charlie.example/up").to_return(status: 200)
    stub_request(:get, "https://charlie.example/peerwatch/status").to_return(status: 503)
    stub_request(:get, "https://delta.example/up").to_return(status: 500)
  end

  def states
    Peerwatch::Check.order(:peer_name).pluck(:peer_name, :state)
  end

  it "records up, detected maintenance and down" do
    described_class.perform_now

    expect(states).to eq([ %w[bravo up], %w[charlie maintenance], %w[delta down] ])
    expect(Peerwatch::Check.find_by(peer_name: "delta")).to have_attributes(status_code: 500, cause: "app")
    expect(a_request(:get, "https://alpha.example/up")).not_to have_been_made
    expect(a_request(:get, "https://delta.example/peerwatch/status")).not_to have_been_made
  end

  it "merges the registry of every peer that sent a report" do
    described_class.perform_now

    expect(Peerwatch::Peer.find_by(name: "echo")).to be_present
    expect(a_request(:get, "https://charlie.example/peerwatch/registry")).not_to have_been_made
  end

  it "caches each peer's report" do
    freeze_time do
      described_class.perform_now

      expect(Rails.cache.read("peerwatch/report/bravo"))
        .to eq("fetched_at" => Time.current.utc.iso8601, "kind" => "ok", "body" => bravo_report)
      expect(Rails.cache.read("peerwatch/report/charlie")).to include("kind" => "maintenance", "body" => nil)
      expect(Rails.cache.read("peerwatch/report/delta")).to include("kind" => "unreachable", "body" => nil)
    end
  end

  it "hands the reports to the evaluator" do
    evaluator = instance_double(Peerwatch::Evaluator, call: nil)
    expect(Peerwatch::Evaluator).to receive(:new).with(reports: { "bravo" => bravo_report }).and_return(evaluator)

    described_class.perform_now
  end

  it "records up without fetching status when the API is off" do
    Peerwatch.config.token = nil

    described_class.perform_now

    expect(states).to eq([ %w[bravo up], %w[charlie up], %w[delta down] ])
    expect(a_request(:get, "https://bravo.example/peerwatch/status")).not_to have_been_made
  end

  it "prunes checks older than retention_days" do
    old = add_check("bravo", "up", at: 31.days.ago)
    kept = add_check("bravo", "up", at: 29.days.ago)

    described_class.perform_now

    expect(Peerwatch::Check.exists?(old.id)).to be(false)
    expect(Peerwatch::Check.exists?(kept.id)).to be(true)
  end

  it "joins through the seed when it knows no peers yet" do
    Peerwatch::Peer.where.not(name: "alpha").delete_all
    Peerwatch.config.seed_url = "https://bravo.example"
    bravo_row = { "name" => "bravo", "url" => "https://bravo.example", "revision_at" => Time.current.iso8601(6) }
    stub_request(:get, "https://bravo.example/peerwatch/registry")
      .to_return(status: 200, body: { peers: [ bravo_row ] }.to_json)

    described_class.perform_now

    expect(states).to eq([ %w[bravo up] ])
  end

  context "when this app's rules block every peer" do
    let(:notices) { [] }

    before do
      Peerwatch.config.notifier = ->(payload) { notices << payload }
      Peerwatch::Peer.where.not(name: "alpha").update_all(contact_emails: [ "ops@elsewhere.example" ])
      Peerwatch.config.allowed_contact_domains = %w[alpha.example]
    end

    it "probes nobody and tells the notifier once per peer" do
      described_class.perform_now
      described_class.perform_now

      expect(Peerwatch::Check.count).to eq(0)
      expect(notices.map { |n| [ n[:event], n[:peer] ] })
        .to eq([ [ :blocked, "bravo" ], [ :blocked, "charlie" ], [ :blocked, "delta" ] ])
      expect(notices.first[:subject]).to start_with("Peerwatch: bravo is blocked by alpha's rules (noticed ")
      expect(notices.first[:body]).to include("allowed_contact_domains", "alpha is watching nobody")
      expect(notices.first[:body]).not_to include("elsewhere.example")
    end

    it "tells the notifier again after a day" do
      described_class.perform_now
      travel_to(25.hours.from_now) { described_class.perform_now }

      expect(notices.count { |n| n[:peer] == "bravo" }).to eq(2)
      expect(notices.map { |n| n[:subject] }.uniq.size).to eq(6)
    end

    it "does not call a notifier it cannot remember having called" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)

      described_class.perform_now

      expect(notices).to be_empty
    end

    it "pulls the repaired rows from the seed and probes again in the same run" do
      Peerwatch.config.seed_url = "https://bravo.example"
      fixed = %w[bravo charlie delta].map do |name|
        { "name" => name, "url" => "https://#{name}.example", "health_path" => "/up",
          "contact_emails" => [ "ops@alpha.example" ], "revision_at" => 1.minute.from_now.iso8601(6) }
      end
      stub_request(:get, "https://bravo.example/peerwatch/registry")
        .to_return(status: 200, body: { peers: fixed }.to_json)

      described_class.perform_now

      expect(states).to eq([ %w[bravo up], %w[charlie maintenance], %w[delta down] ])
      expect(notices).to be_empty
    end

    it "asks nobody when there is no seed" do
      described_class.perform_now

      expect(a_request(:get, %r{/peerwatch/registry})).not_to have_been_made
    end
  end

  it "reports one blocked peer among permitted ones, and again if it is blocked a second time" do
    notices = []
    Peerwatch.config.notifier = ->(payload) { notices << payload }
    # bravo's registry adds echo on the first run, so later runs probe it.
    stub_request(:get, "https://echo.example/up").to_return(status: 200)
    stub_request(:get, "https://echo.example/peerwatch/status").to_return(status: 503)
    delta = Peerwatch::Peer.find_by!(name: "delta")
    delta.update_columns(ip: "10.0.0.1")

    described_class.perform_now
    expect(notices.map { |n| n[:peer] }).to eq([ "delta" ])
    expect(notices.first[:body]).not_to include("watching nobody")

    delta.update_columns(ip: nil)
    described_class.perform_now
    delta.update_columns(ip: "10.0.0.1")
    described_class.perform_now

    expect(notices.map { |n| n[:peer] }).to eq(%w[delta delta])
  end

  it "does nothing without a self_name" do
    Peerwatch.config.self_name = nil

    described_class.perform_now

    expect(Peerwatch::Check.count).to eq(0)
  end

  it "never raises out of perform" do
    allow(Peerwatch::Probe).to receive(:call).and_raise(RuntimeError, "probe exploded")
    allow(Peerwatch::Evaluator).to receive(:new).and_raise(RuntimeError, "evaluator exploded")

    expect { described_class.perform_now }.not_to raise_error
  end

  it "keeps probing the other peers when one probe raises" do
    allow(Peerwatch::Probe).to receive(:call).and_call_original
    allow(Peerwatch::Probe).to receive(:call).with(url: "https://charlie.example/up", ip: nil).and_raise("boom")

    described_class.perform_now

    expect(states).to eq([ %w[bravo up], %w[delta down] ])
  end

  it "skips an existing peer this app's rules now block, logging once per run" do
    Peerwatch::Peer.find_by!(name: "charlie").update_columns(url: "https://169.254.169.254")
    Peerwatch::Peer.find_by!(name: "delta").update_columns(ip: "10.0.0.1")
    logged = []
    allow(Rails.logger).to receive(:warn) { |message| logged << message }

    described_class.perform_now

    expect(states).to eq([ %w[bravo up] ])
    expect(a_request(:any, /169\.254\.169\.254/)).not_to have_been_made
    expect(a_request(:get, "https://delta.example/up")).not_to have_been_made
    blocked_lines = logged.grep(/blocked by this app's rules/)
    expect(blocked_lines.size).to eq(1)
    expect(blocked_lines.first).to include("2 peer(s)", "charlie (", "delta (")
  end

  it "uses the configured queue" do
    Peerwatch.config.queue_name = :monitoring

    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue("monitoring")
  end
end
