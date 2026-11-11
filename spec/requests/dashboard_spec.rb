RSpec.describe "Peerwatch dashboard" do
  before do
    create_peer("charlie")
    create_peer("bravo", environment: "production", maintenance_until: 20.minutes.from_now, maintenance_note: "db upgrade")
    create_peer("alpha")
    create_peer("delta")
    create_peer("echo").remove!

    add_check("bravo", "up", at: 2.minutes.ago, latency_ms: 87)
    add_check("charlie", "down", at: 2.minutes.ago)
    Rails.cache.write("peerwatch/report/bravo", {
      "fetched_at" => Time.current.iso8601, "kind" => "ok",
      "body" => report("bravo", observations: { "alpha" => false, "charlie" => true }).tap do |r|
        r["observations"].find { |o| o["peer"] == "alpha" }["state"] = "maintenance"
      end
    })
    Rails.cache.write("peerwatch/report/charlie", { "fetched_at" => Time.current.iso8601, "kind" => "maintenance", "body" => nil })
    Peerwatch::Incident.create!(peer_name: "charlie", started_at: 4.minutes.ago)
    Peerwatch::Incident.create!(peer_name: "delta", started_at: 2.days.ago, resolved_at: 1.day.ago,
                                planned: true, alerted_by: "bravo")
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def cell(peer, observer_index)
    page.css("#peerwatch-matrix tr[data-peer='#{peer}'] td")[observer_index].text.strip
  end

  it "renders inside the host layout, this app first, without any outbound request" do
    get "/peerwatch"

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#host-home-link")["href"]).to eq("/home")
    expect(page.css("#peerwatch-matrix tbody tr").map { |tr| tr["data-peer"] }).to eq(%w[alpha bravo charlie delta])
    expect(page.css("#peerwatch-matrix thead th").map(&:text).first(5))
      .to eq([ "App", "alpha (this app)", "bravo", "charlie", "delta" ])
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it "shows each observer's view, with no data for an observer in maintenance" do
    get "/peerwatch"

    # Columns: alpha (local checks), bravo (cached report), charlie (maintenance), delta (no report).
    expect([ cell("alpha", 0), cell("alpha", 1), cell("alpha", 2), cell("alpha", 3) ])
      .to eq([ "—", "maintenance", "no data", "no data" ])
    expect([ cell("bravo", 0), cell("bravo", 1), cell("bravo", 2) ]).to eq([ "up", "—", "no data" ])
    expect([ cell("charlie", 0), cell("charlie", 1), cell("charlie", 2) ]).to eq([ "down", "down", "—" ])
    expect(cell("delta", 0)).to eq("no data")
    expect(page.at_css("tr[data-peer='charlie'] .badge.text-bg-danger")).to be_present
    expect(page.at_css("tr[data-peer='bravo'] .badge.text-bg-success")).to be_present
  end

  it "shows environment, uptime, latency, maintenance and incidents" do
    get "/peerwatch"

    bravo = page.at_css("tr[data-peer='bravo']").text
    expect(bravo).to include("production", "100.00%", "87 ms", "maintenance until", "db upgrade")
    expect(page.at_css("tr[data-peer='delta']").text).to include("—")
    expect(response.body).to include("Manage peers")
    expect(page.text).to include("bravo") # alerted_by on the resolved planned incident
    expect(page.css("table").size).to eq(3)
  end

  it "marks a peer this app's rules block, and only that one" do
    Peerwatch::Peer.find_by!(name: "delta").update_columns(url: "https://10.0.0.9")

    get "/peerwatch"

    delta = page.at_css("tr[data-peer='delta'] th")
    expect(delta.at_css(".badge.text-bg-warning").text).to eq("blocked by this app's rules")
    expect(delta.text).to include("must not point at a loopback, private or link-local address")
    expect(page.css(".badge.text-bg-warning").size).to eq(1)
  end
end

RSpec.describe "Peerwatch dashboard on a fresh install" do
  it "renders with no peers at all" do
    get "/peerwatch"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No peers yet.")
  end

  it "renders without a self_name, and says so" do
    Peerwatch.config.self_name = nil
    create_peer("alpha")
    create_peer("bravo")

    get "/peerwatch"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("no <code>self_name</code> configured")
    expect(response.body).not_to include("(this app)")
  end
end
