require "rails/generators"

module Peerwatch
  module Generators
    # Copies the engine's views into the host, like devise:views. A copied
    # file wins over the gem's, so the host can restyle a page, convert it to
    # its own template language, or fill in the empty page chrome.
    class ViewsGenerator < Rails::Generators::Base
      source_root File.expand_path("../../../../app/views/peerwatch", __dir__)
      desc "Copies Peerwatch's views into app/views/peerwatch so you can change them."

      GROUPS = {
        "chrome" => "_page_chrome.html.erb",
        "dashboard" => "dashboard",
        "peers" => "peers",
        "mailer" => "alert_mailer"
      }.freeze

      class_option :views, aliases: "-v", type: :array, default: GROUPS.keys,
                           desc: "Only these groups: #{GROUPS.keys.join(", ")}"

      def check_groups
        unknown = options[:views] - GROUPS.keys
        return if unknown.empty?

        raise Thor::Error, "Unknown view group(s): #{unknown.join(", ")}. Choose from: #{GROUPS.keys.join(", ")}."
      end

      def copy_views
        options[:views].each do |group|
          source = GROUPS.fetch(group)
          destination = File.join("app/views/peerwatch", source)
          if File.directory?(File.join(self.class.source_root, source))
            directory source, destination
          else
            copy_file source, destination
          end
        end
      end

      def show_next_steps
        say <<~STEPS

          Your copies in app/views/peerwatch now take precedence over the gem's.
          Delete any you don't change, so they keep tracking the gem on upgrades.
          See "Making it look native" in docs/INSTALLATION.md.
        STEPS
      end
    end
  end
end
