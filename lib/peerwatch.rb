require "peerwatch/version"
require "peerwatch/configuration"
require "peerwatch/address"
require "peerwatch/probe"
require "peerwatch/client"
require "peerwatch/registry_merge"
require "peerwatch/sync"
require "peerwatch/evaluator"
require "peerwatch/uptime"
require "peerwatch/status_report"
require "peerwatch/alert_text"
require "peerwatch/engine"

module Peerwatch
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = Configuration.new
    end

    # Every failure inside Peerwatch is logged and swallowed: a watcher that
    # raises into the host's error reporting becomes the incident.
    def quietly(context)
      yield
    rescue StandardError => e
      logger&.error("[Peerwatch] #{context}: #{e.class}: #{e.message}")
      nil
    end

    def logger
      defined?(Rails) ? Rails.logger : nil
    end
  end
end
