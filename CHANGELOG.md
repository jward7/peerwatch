# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0, a minor
version may change the API or configuration.

## 0.1.2 — 2026-11-11

### Fixed

- Inside the Peerwatch admin pages, the host's named route helpers now take precedence
  over the engine's. Before, a host `before_action` that called a helper sharing a name
  with an engine route (such as `redirect_to dashboard_path`) got the engine's route,
  without its mount prefix, and redirected to `/`.

### Security

- Registry rows are now treated as untrusted, wherever they come from (another app or
  this app's own peers page). Before, anyone holding the shared token could write a row
  that made every app send requests, with the token attached, to any address its
  servers could reach (loopback, a private network, a cloud metadata service), and
  observe the result as up or down with a status code; and could have alert mail sent to
  any address.
  - Peerwatch no longer connects to loopback, private (RFC 1918 and IPv6 unique-local),
    link-local, unspecified, multicast or other non-public addresses, including
    IPv4-mapped IPv6 forms. The peers page and registry sync refuse a row whose URL is
    such an IP address or `localhost` (or `*.localhost`), or whose stored IP address is
    not a public one. Every request resolves the name first, refuses it if any resolved
    address is not public, and connects to the address it checked, so the name cannot
    re-resolve in between. This covers the seed URL and the stored-IP fallback too. A
    refused request is a failed check (error class `Peerwatch::Address::NotPublic`) or an
    unreachable reply, and no request is sent. New setting `allow_private_addresses`
    (default `false`) turns this off for local testing.
  - New optional allowlists, `allowed_peer_hosts` and `allowed_contact_domains` (default
    `nil`, meaning any). When set, a peer URL's host, and every contact email's domain,
    must be in the list. Setting both in production is recommended.
  - A row from another app that breaks these rules is skipped with a logged warning
    naming the peer and the rule; the rest of the registry still applies.
  - Stored rows are checked as they are used, so tightening the rules takes effect at
    once: a row that breaks them is not probed, synced with, counted as an observer or
    emailed, and the dashboard marks it "blocked by this app's rules".
  - Outbound requests ignore `http_proxy` and `https_proxy`, since a proxy would resolve
    peer names itself. Redirects are still never followed.
- What a token holder can still do is set out in the README's "Security and trust
  model": one shared secret still protects the whole mesh.

### Upgrade notes

- An app that tests against `localhost` or another private address (two local apps, a
  Docker network) must set `config.allow_private_addresses = true` there, in development
  only.
- Existing rows that break the new rules stop being probed, synced with and emailed, and
  show as blocked on the dashboard. Fix the row (or the rules) on the peers page.
- An app that reaches the internet only through an HTTP proxy can no longer probe.

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
