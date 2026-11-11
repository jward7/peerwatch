require "generators/peerwatch/views/views_generator"

RSpec.describe Peerwatch::Generators::ViewsGenerator do
  def run_generator(args)
    Dir.mktmpdir do |dir|
      silence_stdout { described_class.start(args, destination_root: dir) }
      yield Dir.chdir(dir) { Dir["app/views/**/*"].select { |path| File.file?(path) }.sort }, dir
    end
  end

  it "copies every view by default, unchanged" do
    engine_views = Dir.chdir(File.expand_path("../../app/views", __dir__)) { Dir["peerwatch/**/*.erb"] }

    run_generator([]) do |copied, dir|
      expect(copied).to match_array(engine_views.map { |path| "app/views/#{path}" })
      engine_views.each do |path|
        expect(File.read(File.join(dir, "app/views", path)))
          .to eq(File.read(File.expand_path("../../app/views/#{path}", __dir__)))
      end
    end
  end

  it "copies only the chosen groups" do
    run_generator(%w[-v chrome peers]) do |copied|
      expect(copied).to include("app/views/peerwatch/_page_chrome.html.erb", "app/views/peerwatch/peers/_form.html.erb")
      expect(copied.grep(%r{/dashboard/|/alert_mailer/})).to be_empty
    end
  end

  it "refuses an unknown group" do
    expect { silence_stdout { described_class.start(%w[-v sidebar], destination_root: Dir.mktmpdir) } }
      .to output(/Unknown view group\(s\): sidebar/).to_stderr
  end

  def silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
