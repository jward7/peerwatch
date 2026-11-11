# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0, a minor
version may change the API or configuration.

## 0.1.1 — 2026-11-11

### Fixed

- Registry sync ignores a row whose `revision_at` is more than five minutes in the
  future, and logs a warning. Before, one app with a fast clock could stamp a row that
  no later edit in any app could replace until real time caught up.

## 0.1.0 — 2026-11-11

First release.

### Added

- A mountable Rails engine (`mount Peerwatch::Engine, at: "/peerwatch"`) and an install
  generator (`bin/rails g peerwatch:install`) that writes a commented initializer.
- `Peerwatch::ProbeJob`, meant to run every two minutes: probes each peer's health URL,
  fetches its status report, pulls its registry, evaluates incidents and prunes old checks.
  It never raises; failures are logged with a `[Peerwatch]` prefix.
- An optional IP address per peer, used to tell a DNS failure from an app failure.
- Two token-protected JSON endpoints, `/peerwatch/status` and `/peerwatch/registry`
  (GET and POST). A missing, wrong or unconfigured token gets an empty 404.
- A shared registry of peers, synced by a push on every edit and a pull on every probe
  cycle. The newest revision of a row wins; removed peers are kept as tombstones so the
  removal syncs, and adding a removed name again restores that row.
- Alerting with a quorum (another observer must agree, except in a two-app mesh), one
  elected email sender with a fallback, recovery emails, and a `notifier` callback.
- Maintenance handling: detected (health URL up, status endpoint 503) and declared (a
  window on the peers page or `bin/rails peerwatch:maintenance`). Neither alerts; a
  declared window that overruns alerts once, worded as an overrun.
- An admin dashboard (every app as seen by every observer, 24-hour, 7-day and 30-day
  uptime, open and recent incidents) and a peers page, rendered in the host's layout
  behind the host's own admin controller.
- Support for Rails 8.0 and 8.1 on Ruby 3.2 to 3.4, tested on SQLite and PostgreSQL.
