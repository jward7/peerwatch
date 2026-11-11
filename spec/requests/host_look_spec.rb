# The dummy host overrides peerwatch/_page_chrome (spec/dummy/app/views) to
# fill its layout's breadcrumb bar, and marks its nav item active by
# controller_path, as docs/INSTALLATION.md describes.
RSpec.describe "Peerwatch pages inside the host's look" do
  def page
    Nokogiri::HTML(response.body)
  end

  def crumbs
    page.css("#host-breadcrumbs li").map { |li| [ li.text.strip, li.at_css("a")&.[]("href"), li["data-section"] ] }
  end

  it "sets the title and breadcrumbs on the dashboard" do
    get "/peerwatch"

    expect(page.at_css("title").text).to eq("Peerwatch")
    expect(crumbs).to eq([ [ "Peerwatch", nil, "dashboard" ] ])
  end

  it "sets the title and breadcrumbs on the peers pages" do
    create_peer("bravo")

    get "/peerwatch/peers"
    expect(page.at_css("title").text).to eq("Peerwatch · Peers")
    expect(crumbs).to eq([ [ "Peerwatch", "/peerwatch/", "peers" ], [ "Peers", nil, "peers" ] ])

    get "/peerwatch/peers/new"
    expect(crumbs.map(&:first)).to eq([ "Peerwatch", "Peers", "Add a peer" ])
    expect(crumbs[1][1]).to eq("/peerwatch/peers")

    get "/peerwatch/peers/#{Peerwatch::Peer.find_by!(name: "bravo").id}/edit"
    expect(page.at_css("title").text).to eq("Peerwatch · Peers · Edit bravo")
  end

  it "lets the host mark its own nav item active" do
    get "/peerwatch/peers"
    expect(page.at_css("#host-peerwatch-link")["class"]).to eq("active")

    get "/home"
    expect(page.at_css("#host-peerwatch-link")["class"]).to be_blank
  end

  it "leaves layout and spacing to the host" do
    get "/peerwatch"

    root = page.at_css(".peerwatch")
    expect(root["class"].split).to contain_exactly("peerwatch", "peerwatch-dashboard")
    expect(response.body).not_to match(/class="[^"]*\bcontainer(-fluid)?\b/)
  end

  it "uses a host's copy of a view over the gem's" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "peerwatch/dashboard"))
      File.write(File.join(dir, "peerwatch/dashboard/_state_badge.html.erb"), %(<b class="host-badge"><%= state %></b>))
      Peerwatch::DashboardController.prepend_view_path(dir)
      create_peer("alpha")
      create_peer("bravo")
      add_check("bravo", "up", at: 1.minute.ago)

      get "/peerwatch"

      expect(page.css("b.host-badge").map(&:text)).to include("up")
    ensure
      Peerwatch::DashboardController.view_paths = Peerwatch::DashboardController.view_paths.reject { |path| path.to_s == dir }
    end
  end
end
