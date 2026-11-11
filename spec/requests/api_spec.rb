RSpec.describe "Peerwatch API" do
  let(:auth) { { "Authorization" => "Bearer secret" } }

  before do
    create_peer("alpha")
    create_peer("bravo")
    create_peer("charlie").remove!
  end

  %w[/peerwatch/status /peerwatch/registry].each do |path|
    describe "GET #{path}" do
      it "is an empty 404 without a token" do
        get path

        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_empty
      end

      it "is a 404 with the wrong token" do
        get path, headers: { "Authorization" => "Bearer wrong" }
        expect(response).to have_http_status(:not_found)

        get path, headers: { "Authorization" => "Bearer secret-and-more" }
        expect(response).to have_http_status(:not_found)

        get path, headers: { "Authorization" => "secret" }
        expect(response).to have_http_status(:not_found)
      end

      it "is a 404 when no token is configured, whatever is presented" do
        Peerwatch.config.token = ""

        get path, headers: { "Authorization" => "Bearer " }

        expect(response).to have_http_status(:not_found)
      end

      it "answers with the token" do
        get path, headers: auth

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
      end
    end
  end

  it "returns the status report" do
    get "/peerwatch/status", headers: auth

    expect(response.parsed_body).to include("name" => "alpha", "version" => Peerwatch::VERSION, "can_email" => true)
  end

  it "returns every registry row, tombstones included" do
    get "/peerwatch/registry", headers: auth

    rows = response.parsed_body["peers"]
    expect(rows.map { |r| r["name"] }).to eq(%w[alpha bravo charlie])
    expect(rows.last["removed_at"]).to be_present
  end

  it "applies pushed rows" do
    rows = [
      { name: "delta", url: "https://delta.example", health_path: "/up", contact_emails: [ "ops@example.com" ],
        maintenance_until: 1.hour.from_now.iso8601(6), revision_at: Time.current.iso8601(6) },
      { name: "Bad Name", url: "https://bad.example", revision_at: Time.current.iso8601(6) }
    ]

    post "/peerwatch/registry", params: { peers: rows }.to_json,
                                headers: auth.merge("Content-Type" => "application/json")

    expect(response.parsed_body).to eq("applied" => 1)
    expect(Peerwatch::Peer.find_by!(name: "delta")).to have_attributes(contact_emails: [ "ops@example.com" ])
    expect(Peerwatch::Peer.find_by!(name: "delta").in_maintenance?).to be(true)
  end

  it "applies nothing from a malformed push" do
    post "/peerwatch/registry", params: { peers: "nope" }.to_json,
                                headers: auth.merge("Content-Type" => "application/json")

    expect(response.parsed_body).to eq("applied" => 0)
  end

  it "refuses a push without the token" do
    post "/peerwatch/registry", params: { peers: [] }.to_json, headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:not_found)
  end
end
