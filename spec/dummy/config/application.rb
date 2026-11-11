require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"

require "peerwatch"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    # The suite runs on every supported Rails minor (see the CI matrix).
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.enable_reloading = false
    config.consider_all_requests_local = true
    config.action_controller.allow_forgery_protection = false
    config.action_dispatch.show_exceptions = :none
    config.active_job.queue_adapter = :test
    config.action_mailer.delivery_method = :test
    config.action_mailer.default_url_options = { host: "alpha.example" }
    config.cache_store = :memory_store
    config.secret_key_base = "dummy-secret-key-base-for-specs-only"
    config.hosts.clear
    config.logger = Logger.new(nil)
    config.active_support.deprecation = :stderr
  end
end
