require "rails/generators"

module Peerwatch
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Creates config/initializers/peerwatch.rb and prints the remaining install steps."

      def copy_initializer
        template "peerwatch.rb", "config/initializers/peerwatch.rb"
      end

      def show_next_steps
        say <<~STEPS

          Peerwatch: next steps

          1. Copy and run the migrations:
               bin/rails peerwatch:install:migrations
               bin/rails db:migrate

          2. Mount the engine in config/routes.rb, outside any admin-only
             constraint (the API endpoints are reached by the other apps;
             the admin pages are gated by admin_parent_controller):
               mount Peerwatch::Engine, at: "/peerwatch"

          3. Schedule the probe in config/recurring.yml, under the key of each
             environment that should run it:
               production:
                 peerwatch_probe:
                   class: Peerwatch::ProbeJob
                   schedule: every 2 minutes

          4. In config/initializers/peerwatch.rb, set self_name, the shared token
             and admin_parent_controller (an admin-only controller), then add this
             app's own row on /peerwatch/peers.

          5. Optional: fit the admin pages into your breadcrumbs and nav, or
             restyle them:
               bin/rails g peerwatch:views -v chrome   # or all views, without -v

          Full guide: https://github.com/jward7/peerwatch/blob/main/docs/INSTALLATION.md
        STEPS
      end
    end
  end
end
