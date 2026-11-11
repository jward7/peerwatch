# Set at boot, as a host would: the parent classes are read when the engine's
# controllers and mailer load, before any spec's before hook runs.
Peerwatch.configure do |config|
  config.mailer_parent = "ApplicationMailer"
end
