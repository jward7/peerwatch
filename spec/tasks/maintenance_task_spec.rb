require "rake"

RSpec.describe "peerwatch:maintenance" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "peerwatch:maintenance" } }

  let(:task) { Rake::Task["peerwatch:maintenance"] }

  def run_task(env)
    task.reenable
    old = env.keys.to_h { |k| [ k, ENV[k] ] }
    env.each { |k, v| ENV[k] = v }
    task.invoke
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  before do
    create_peer("alpha")
    create_peer("bravo")
    create_peer("charlie")
    stub_request(:post, "https://bravo.example/peerwatch/registry").to_return(status: 200, body: "{}")
    stub_request(:post, "https://charlie.example/peerwatch/registry").to_return(status: 503)
  end

  it "declares a window and pushes it synchronously" do
    freeze_time do
      expect { run_task("MINUTES" => "30", "NOTE" => "db upgrade") }
        .to output(/maintenance until .*; 1 of 2 peers accepted it/).to_stdout

      expect(Peerwatch::Peer.find_by!(name: "alpha"))
        .to have_attributes(maintenance_until: 30.minutes.from_now, maintenance_note: "db upgrade")
    end
    expect(a_request(:post, "https://bravo.example/peerwatch/registry")
      .with { |req| JSON.parse(req.body)["peers"].first["maintenance_note"] == "db upgrade" }).to have_been_made
  end

  it "clears the window with MINUTES=0" do
    Peerwatch::Peer.find_by!(name: "alpha").update!(maintenance_until: 1.hour.from_now, maintenance_note: "x")

    expect { run_task("MINUTES" => "0", "NOTE" => nil) }.to output(/maintenance cleared/).to_stdout

    expect(Peerwatch::Peer.find_by!(name: "alpha")).to have_attributes(maintenance_until: nil, maintenance_note: nil)
  end

  it "aborts when self_name is unset" do
    Peerwatch.config.self_name = nil

    expect { run_task("MINUTES" => "30") }.to raise_error(SystemExit).and output(/self_name is not set/).to_stderr
  end

  it "aborts when this app has no peer row" do
    Peerwatch::Peer.find_by!(name: "alpha").destroy!

    expect { run_task("MINUTES" => "30") }.to raise_error(SystemExit).and output(/no peer row named "alpha"/).to_stderr
  end
end
