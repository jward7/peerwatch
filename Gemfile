source "https://rubygems.org"

gemspec

# CI pins the Rails minor, e.g. RAILS_VERSION=8.0; unset means the newest
# release the gemspec allows.
gem "rails", "~> #{ENV["RAILS_VERSION"]}.0" if ENV["RAILS_VERSION"].to_s != ""
# Rails 8.0's JSON encoder passes quirks_mode:, which json 3.x rejects.
gem "json", "< 3" if ENV["RAILS_VERSION"] == "8.0"

gem "rake"
gem "rspec-rails"
gem "rubocop-rails-omakase", require: false
gem "sqlite3"
gem "webmock"

# Only for running the suite against PostgreSQL (DATABASE_URL=postgres://...).
# Optional, so `bundle install` never needs libpq; enable it with
#   bundle config set --local with postgres
group :postgres, optional: true do
  gem "pg"
end
