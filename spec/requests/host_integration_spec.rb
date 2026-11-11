RSpec.describe "Peerwatch inside a host app" do
  it "lets the host's before_action redirect with a host route helper" do
    get "/peerwatch", params: { locked: 1 }

    expect(response).to redirect_to("/home")
  end
end
