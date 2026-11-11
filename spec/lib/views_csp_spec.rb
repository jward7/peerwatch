# Hosts enforce a strict Content Security Policy, which a spec cannot see
# being violated. Keep the views free of what it would block.
RSpec.describe "engine views" do
  Dir[File.expand_path("../../app/views/**/*.erb", __dir__)].each do |path|
    it "#{path.split("app/views/").last} has no inline script, style or handler" do
      source = File.read(path)

      expect(source).not_to match(/<script/i)
      expect(source).not_to match(/\sstyle\s*=/i)
      expect(source).not_to match(/\son[a-z]+\s*=/i)
      expect(source).not_to match(/javascript:/i)
    end
  end
end
