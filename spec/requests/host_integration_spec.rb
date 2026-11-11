RSpec.describe "Peerwatch inside a host app" do
  it "lets the host's before_action redirect with a host route helper" do
    get "/peerwatch", params: { locked: 1 }

    expect(response).to redirect_to("/home")
  end

  it "resolves a host route helper that shares its name with an engine route" do
    get "/peerwatch", params: { refused: 1 }

    expect(response).to redirect_to("/dashboard")
  end

  it "still reaches the engine's own routes through the mounted helper" do
    get "/peerwatch/peers"

    expect(response.body).to include('href="/peerwatch/"')
  end
end
