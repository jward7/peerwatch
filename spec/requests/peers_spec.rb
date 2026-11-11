RSpec.describe "Peerwatch peers admin" do
  let(:attrs) do
    { name: "bravo", url: "https://bravo.example", health_path: "/up", environment: "production",
      contact_emails_text: "ops@example.com\nadmin@example.com", maintenance_until: "", maintenance_note: "" }
  end

  it "lists live peers and the removed ones inside the host layout" do
    create_peer("alpha")
    create_peer("charlie").remove!

    get "/peerwatch/peers"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("host-home-link", "alpha (this app)", "Removed peers (1)")
  end

  it "renders the new and edit forms" do
    peer = create_peer("bravo")

    get "/peerwatch/peers/new"
    expect(response).to have_http_status(:ok)

    get "/peerwatch/peers/#{peer.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("input[name='peer[name]']")["readonly"]).to be_present
  end

  it "creates a peer and pushes it" do
    expect { post "/peerwatch/peers", params: { peer: attrs } }
      .to have_enqueued_job(Peerwatch::PushJob).with("bravo")

    expect(response).to redirect_to("/peerwatch/peers")
    expect(Peerwatch::Peer.find_by!(name: "bravo").contact_emails).to eq([ "ops@example.com", "admin@example.com" ])
  end

  it "restores a removed peer of the same name and pushes it" do
    removed = create_peer("bravo", url: "https://old-bravo.example")
    removed.remove!

    expect { post "/peerwatch/peers", params: { peer: attrs } }
      .to have_enqueued_job(Peerwatch::PushJob).with("bravo")

    expect(response).to redirect_to("/peerwatch/peers")
    expect(flash[:notice]).to start_with("bravo restored")
    expect(Peerwatch::Peer.count).to eq(1)
    expect(removed.reload).to have_attributes(removed_at: nil, url: "https://bravo.example", environment: "production",
                                              contact_emails: [ "ops@example.com", "admin@example.com" ])
  end

  it "re-renders the create form for a removed name with an error, still posting to create" do
    create_peer("bravo").remove!

    post "/peerwatch/peers", params: { peer: attrs.merge(url: "http://bravo.example") }

    expect(response).to have_http_status(:unprocessable_content)
    form = Nokogiri::HTML(response.body).at_css("form")
    expect(form["action"]).to eq("/peerwatch/peers")
    expect(form.at_css("input[name='_method']")).to be_nil
    expect(form.at_css("input[name='peer[name]']")["readonly"]).to be_nil
    expect(Peerwatch::Peer.find_by!(name: "bravo").removed_at).to be_present
  end

  it "still refuses a name a live peer already has" do
    create_peer("bravo")

    post "/peerwatch/peers", params: { peer: attrs }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Name has already been taken")
  end

  it "says how to start when there are no peers" do
    get "/peerwatch/peers"

    expect(response.body).to include("No peers yet.")
  end

  it "re-renders the form on a validation error and pushes nothing" do
    expect { post "/peerwatch/peers", params: { peer: attrs.merge(url: "http://bravo.example") } }
      .not_to have_enqueued_job(Peerwatch::PushJob)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be an https URL")
  end

  it "updates a peer, ignoring a changed name, and pushes it" do
    peer = create_peer("bravo")

    expect {
      patch "/peerwatch/peers/#{peer.id}", params: { peer: { name: "renamed", maintenance_until: "2030-01-01T10:00",
                                                             maintenance_note: "db upgrade" } }
    }.to have_enqueued_job(Peerwatch::PushJob).with("bravo")

    expect(peer.reload).to have_attributes(name: "bravo", maintenance_note: "db upgrade")
    expect(peer.maintenance_until).to eq(Time.zone.parse("2030-01-01 10:00"))
  end

  it "removes a peer as a tombstone and pushes it" do
    peer = create_peer("bravo")

    expect { delete "/peerwatch/peers/#{peer.id}" }.to have_enqueued_job(Peerwatch::PushJob).with("bravo")

    expect(peer.reload.removed_at).to be_present
    expect(Peerwatch::Peer.count).to eq(1)
  end

  it "pushes the row when the push job runs" do
    peer = create_peer("bravo")
    stub = stub_request(:post, "https://bravo.example/peerwatch/registry").to_return(status: 200, body: "{}")

    Peerwatch::PushJob.perform_now(peer.name)

    expect(stub).to have_been_requested
  end
end
