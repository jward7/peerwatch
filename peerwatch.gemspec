require_relative "lib/peerwatch/version"

Gem::Specification.new do |spec|
  spec.name = "peerwatch"
  spec.version = Peerwatch::VERSION
  spec.authors = [ "jward7" ]
  spec.summary = "Rails apps that watch each other: a small uptime mesh as a mountable engine."
  spec.description = "Install Peerwatch in several Rails apps and each one probes the others, " \
                     "shares what it sees, shows one collated dashboard and emails the contacts " \
                     "when a peer is down. Maintenance windows are recorded but never reported."
  spec.homepage = "https://github.com/jward7/peerwatch"
  spec.license = "MIT"
  # Rails 8.0 and 8.1 both require Ruby 3.2 or newer.
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "#{spec.homepage}/blob/main/docs/INSTALLATION.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["{app,config,db,lib,docs}/**/*", "MIT-LICENSE", "README.md", "CHANGELOG.md", "SECURITY.md"]

  # Tested on Rails 8.0 and 8.1. A new major version needs a new release.
  spec.add_dependency "rails", "~> 8.0"
end
