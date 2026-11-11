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

  it "uses the configured queue" do
    Peerwatch.config.queue_name = :monitoring

    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue("monitoring")
  end
end
