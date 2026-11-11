require "generators/peerwatch/install/install_generator"

RSpec.describe Peerwatch::Generators::InstallGenerator do
  it "writes the initializer and prints the next steps" do
    Dir.mktmpdir do |dir|
      output = capture_stdout { described_class.start([], destination_root: dir) }

      initializer = File.read(File.join(dir, "config/initializers/peerwatch.rb"))
      Peerwatch::Configuration.public_instance_methods(false).grep(/=\z/).each do |setter|
        expect(initializer).to include("config.#{setter.to_s.chomp("=")} =")
      end
      expect(output).to include("bin/rails peerwatch:install:migrations", "mount Peerwatch::Engine",
                                "class: Peerwatch::ProbeJob", "schedule: every 2 minutes")
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
