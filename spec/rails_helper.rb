ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "rspec/rails"
require "webmock/rspec"

WebMock.disable_net_connect!

# The schema is the engine's own migration. The default database is SQLite in
# memory; a DATABASE_URL one persists between runs, so start from scratch.
require_relative "../db/migrate/20260101000000_create_peerwatch_tables"
ActiveRecord::Migration.suppress_messages do
  %w[peerwatch_peers peerwatch_checks peerwatch_incidents].each do |table|
    ActiveRecord::Migration.drop_table(table, if_exists: true)
  end
  CreatePeerwatchTables.migrate(:up)
end

Dir[File.join(__dir__, "support/**/*.rb")].each { |file| require file }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.order = :random
  config.include ActiveJob::TestHelper
  config.include ActiveSupport::Testing::TimeHelpers
  config.include PeerwatchHelpers

  config.before do
    Peerwatch.reset_config!
    Peerwatch.configure do |c|
      c.self_name = "alpha"
      c.token = "secret"
      c.allow_http = false
      c.mailer_parent = "ApplicationMailer"
    end
    Rails.cache.clear
    ActionMailer::Base.deliveries.clear
    # No spec touches a real resolver: every name resolves to one public
    # documentation address unless the spec says otherwise (resolve_to).
    allow(Peerwatch::Address).to receive(:resolve).and_return([ PeerwatchHelpers::DEFAULT_ADDRESS ])
  end
end
