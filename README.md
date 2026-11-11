# Peerwatch

[![CI](https://github.com/jward7/peerwatch/actions/workflows/ci.yml/badge.svg)](https://github.com/jward7/peerwatch/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](https://github.com/jward7/peerwatch/blob/main/MIT-LICENSE)

Your Rails apps watch each other and email you when one of them goes down.

You probably run several small Rails apps on different servers. When one goes down, you
hear about it from a user. You don't want to run and babysit another monitoring service
for this, and you don't have to: the apps you already run can watch each other. Add one
`Gemfile` line and one mount to each app. There is no new server, no new vendor and no
agent. Each app probes the others every two minutes. They compare what they see, and
when they agree that one is down, one of them emails that app's contacts.

The dashboard, inside each app's admin, shows every app as seen by every other app
(a plain-text sketch, not a screenshot):

```
               observers →
apps ↓         alpha (this app)   bravo         charlie   delta
alpha          —                  up            no data   no data
bravo          up                 —             no data   no data
charlie        down               down          —         no data
delta          maintenance        maintenance   no data   —
```

Here alpha and bravo agree that charlie is down, so one of them emails charlie's contacts.
Delta is in maintenance, so nobody is told about it. An app that is down or in maintenance
cannot send its own report, which is why its column reads "no data".

**Status:** version 0.1.0. It is new and has not yet run in production. The API and
configuration may change before 1.0.

## Contents

- [Is it for you?](#is-it-for-you)
- [How it works](#how-it-works)
- [How it compares](#how-it-compares)
- [Quick start](#quick-start)
- [Configuration reference](#configuration-reference)
- [Maintenance windows](#maintenance-windows)
- [Alerting rules](#alerting-rules)
- [Security and trust model](#security-and-trust-model)
- [Limitations](#limitations)
- [Development, contributing, security, licence](#development-contributing-security-licence)

The full installation guide is [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Is it for you?

**The sweet spot:**

- You run 2 to 10 Rails apps that you own, spread over at least two servers or providers.
- You are a solo developer or a small team.
- You want outage emails to go to several contacts, and you want one combined view inside
  the admin you already have.
- You already run Solid Queue or another Active Job backend that can run recurring jobs.
- Planned maintenance should not page anyone.

**Not a fit:**

- **A single app.** There is nothing else to watch it.
- **All your apps on one server.** They fail together, and then nobody is left to send the
  email.
- **You need checks from outside your own infrastructure**, multi-region latency,
  browser or synthetic flows, SLA reporting, SMS or phone on-call escalation, or a public
  status page. Use one of the tools in [How it compares](#how-it-compares).
- **Non-Rails services.** Peerwatch can only watch an app that also runs Peerwatch, and
  only Rails apps can.

## How it works

Every app in the mesh runs `Peerwatch::ProbeJob` every two minutes. Each run goes through
five steps.

1. **Probe.** It sends a `GET` to every other app's health URL, which is the app's base
   URL plus `health_path` (default `/up`). Any 2xx answer means up. Anything else is down:
   another status (redirects included), a timeout or a connection error. If you gave the
   peer an IP address and the request failed, Peerwatch tries once more against that
   address, to tell a DNS failure from an app failure.
2. **Share.** If the health URL answered, the job also fetches the peer's
   `/peerwatch/status`, which is that peer's own view of everyone. From each peer that
   sent a report, it then pulls the registry, the shared list of apps with their URLs, contacts and maintenance
   windows. An edit on any app's peers page is pushed to every other app at once and
   repaired by these pulls. For each app in the list, the newest edit wins. A removed app
   stays in the list as a tombstone, so the removal syncs too.
3. **Agree.** After `failure_threshold` failed checks in a row (default 2), the job opens
   an incident for that peer. It alerts only when at least one other observer's latest
   report also says the peer is down. This quorum stops a single app with a bad network
   connection, or an app that is itself cut off, from paging you about apps that are fine.
   In a mesh of exactly two apps there is nobody to agree with, so the app left standing
   alerts alone.
4. **One sender.** Every agreeing app calls its own `notifier`, if you set one, so that
   each host's own channel hears about the outage. Only one app sends the email: the
   first, by name, of the agreeing apps that can send mail. If that app has not sent
   within `fallback_after` (default 8 minutes), any other agreeing app sends instead.
5. **Recover.** After `recovery_threshold` good checks in a row (default 2), the incident
   is resolved. The app that sent the down email sends the recovery email.

Maintenance is recorded but never reported. If a peer's health URL is up but its
`/peerwatch/status` answers 503 (a typical maintenance mode), the check is recorded as
`maintenance`, which counts as up. You can also declare a window in advance; see
[Maintenance windows](#maintenance-windows).

## How it compares

Peerwatch lives inside apps you already run. That makes it cheap to adopt, and it also
limits what it can see. Most people with paying customers should pair it with an outside
monitor. These comparisons are based on what we understood about each tool as of late
2026; check their own docs before you choose.

| | Where it runs | Checks from outside your infrastructure | What it checks | Alerts | What you operate |
|---|---|---|---|---|---|
| **Peerwatch** | Inside your existing Rails apps | No | One HTTP URL per app | Email, plus one callback | No new server or service |
| **Hosted monitors** (UptimeRobot, Better Stack, Pingdom, StatusCake and similar) | The vendor's infrastructure, from several regions | Yes | See each vendor's docs | Include SMS and phone escalation, and status pages | A vendor account (a monthly fee or a limited free tier) |
| **Dead man's switches** (Healthchecks.io-style) | Outside your apps | They receive pings from you | That your pings keep arriving | When the pings stop | Ping calls in your jobs |
| **Uptime Kuma** | A server of its own, which you run | From wherever you run it | See its docs | Many notification channels, and a status page | A self-hosted service and its server |
| **Upright** (37signals) | Its own dedicated Rails app, deployed with Kamal | Yes, from multiple sites | HTTP, Playwright, SMTP and traceroute probes | Through Prometheus and Alertmanager | A Rails app plus Prometheus and Alertmanager |
| **Health-endpoint gems** (Rails' `/up`, OkComputer, `health_check`, `allgood`) | Inside each app | Not applicable | They expose a health URL for something else to poll | None; they do not watch other apps | No new server or service |

**Hosted monitors** check your apps from outside your infrastructure, so they catch the
outages Peerwatch cannot see: a whole provider down, or DNS broken for everyone. If an
app earns money, run one of them alongside Peerwatch. A **dead man's switch** works the
other way round: your app pings it, and it alerts when the pings stop. That makes it good
for cron jobs, and it complements Peerwatch. **Uptime Kuma** is an open-source,
self-hosted monitor. You run and maintain it on a server of its own, and that server
should not be one of the servers it watches. **Upright** is an open-source Rails engine
for synthetic monitoring from multiple sites. It is much more capable than Peerwatch, has
much more to operate, and is aimed at a larger scale. **Health-endpoint gems** combine
well with Peerwatch: point `health_path` at a deeper check than `/up`, and Peerwatch will
poll it.

Peerwatch's own trade-off: there is no extra server or vendor, the registry syncs
itself, nobody is alerted until a second observer agrees, and maintenance is
understood. But it is only as independent as your apps' hosting, it checks one HTTP URL
per app, and it alerts by email plus one callback.

## Quick start

This is the short path. The [installation guide](docs/INSTALLATION.md) covers each step
in detail, including what commonly blocks the endpoints in a host app.

You need Rails 8.0 or newer, Ruby 3.2 or newer, an Active Job backend that runs recurring
jobs, working mail, and HTTPS.

In **each** app:

```ruby
# Gemfile (from git until the gem is released to RubyGems)
gem "peerwatch", git: "https://github.com/jward7/peerwatch", tag: "v0.1.0"
```

```sh
bundle install
bin/rails g peerwatch:install          # writes config/initializers/peerwatch.rb
bin/rails peerwatch:install:migrations
bin/rails db:migrate
```

```ruby
# config/routes.rb: at exactly /peerwatch, OUTSIDE any authenticated or admin-only block
mount Peerwatch::Engine, at: "/peerwatch"
```

```yaml
# config/recurring.yml (Solid Queue), under the key for each environment that should run it
production:
  peerwatch_probe:
    class: Peerwatch::ProbeJob
    schedule: every 2 minutes
```

Generate one token (`bin/rails secret`) and store the **same** value in every app's
credentials as `peerwatch: { token: ... }`. Then edit the initializer:

```ruby
Peerwatch.configure do |config|
  config.self_name = "alpha"                                    # this app's name in the registry
  config.token = Rails.application.credentials.dig(:peerwatch, :token)
  config.admin_parent_controller = "Admin::BaseController"      # an admin-only base controller
  config.mailer_parent = "ApplicationMailer"                    # for your From address
end
```

**First app:** open `/peerwatch/peers` and add a row for this app (its name must equal
`self_name`), then a row for each other app.

**Each further app:** do the same install, set `self_name` to the name the first app gave
it, and set `config.seed_url = "https://alpha.example"` (any app already in the mesh).
On its first probe cycle it pulls the whole registry from there.

Within two cycles each app's dashboard at `/peerwatch` fills in. Then add a nav link to
`peerwatch.dashboard_path` in your admin.

## Configuration reference

Every setting is in `Peerwatch.configure`, and the generated initializer lists them all
with their defaults. `admin_parent_controller` and `mailer_parent` are read once, when
Peerwatch's controllers and mailer load, so set them in the initializer and nowhere else.

| Setting | Default | Meaning |
|---|---|---|
| `self_name` | `nil` | This app's name in the registry. It must match this app's row on the peers page. Nothing is probed or evaluated until it is set. |
| `token` | `nil` | The shared secret every app presents as `Authorization: Bearer <token>`. Blank turns off the API endpoints and all syncing; probing still runs. |
| `seed_url` | `nil` | One existing app's base URL, used to join the mesh before the registry has synced. Optional once peers are known. |
| `admin_parent_controller` | `"ApplicationController"` | The class the admin pages inherit, as a string. Point it at a controller that only lets admins in. |
| `layout` | `"application"` | The layout the admin pages render in. |
| `mailer_parent` | `"ActionMailer::Base"` | The class the alert mailer inherits, as a string, so your From address and interceptors apply. |
| `can_email` | `true` | Set to `false` for an app whose mail reaches nobody (a staging mail catcher). It still observes and votes, but never sends alert mail. |
| `notifier` | `nil` | A callable, given `{ event:, peer:, subject:, body: }` once per down and recovery event. See [Alerting rules](#alerting-rules). |
| `queue_name` | `:default` | The queue for `ProbeJob` and `PushJob`. |
| `open_timeout` | `5` | Seconds to wait to connect, for every outbound request. |
| `read_timeout` | `5` | Seconds to wait for an answer, for every outbound request. |
| `failure_threshold` | `2` | Failed checks in a row before a peer counts as down. Use 1 or more. |
| `recovery_threshold` | `2` | Good checks in a row before a down peer counts as recovered. Use 1 or more. |
| `fallback_after` | `480` (`8 * 60`) | Seconds the elected sender has before another agreeing app sends the email instead. |
| `retention_days` | `30` | Days of checks to keep. Older checks are deleted at the end of each cycle. Incidents are kept. |
| `allow_http` | `false` | Accept plain `http` peer URLs. For local testing only: the token would travel unencrypted. |

Every outbound request carries `User-Agent: peerwatch/<version>`. `Net::HTTP`'s
automatic retry is turned off, so the two timeouts are the real limit on each request.

## Maintenance windows

Every check is `up`, `maintenance` or `down`. Peerwatch learns that a peer is in
maintenance in one of two ways.

**Detected.** Many apps keep their health URL answering during maintenance while a
maintenance mode returns 503 for everything else. If the health URL is up and
`/peerwatch/status` answers 503, the check is recorded as `maintenance`. It counts as up
and never alerts, and the host needs no changes. (Peerwatch cannot tell a maintenance
503 from any other 503 on that path.)

**Declared.** When the app will really be down (a proxy maintenance page, a database
upgrade, a reboot), its health URL fails, and that looks exactly like an outage. Declare
a window first, either on the peers page (edit the app's row and set "Maintenance until")
or from the app itself just before it goes down:

```sh
bin/rails peerwatch:maintenance MINUTES=30 NOTE="db upgrade"   # MINUTES=0 clears the window
```

The task saves the window to this app's own row and pushes it to every peer straight
away. It then prints how many accepted it, for example
`Peerwatch: maintenance until 2026-01-05 03:42 UTC; 2 of 2 peers accepted it.`

While the window is open, failures are recorded as a *planned* incident and nobody is
told. If the peer recovers inside the window, the incident closes silently. If it is
still down when the window ends, the normal alert goes out, worded as an overrun
(`... is still down after its maintenance window ...`), and the `fallback_after` wait
starts from the end of the window. Uptime figures leave planned downtime out.

## Alerting rules

- **Down.** An app counts a peer as down after `failure_threshold` failed checks in a
  row, from its own checks only. The incident starts at the first check of that run.
- **Quorum.** It alerts only when at least one other live observer's report, fetched in
  the same cycle, also says the peer is down. If the other observers say the peer is up,
  or none of them answered, it stays quiet and logs that it did. The one exception is a
  mesh of two apps, where the one left standing alerts alone.
- **Notifier.** Once quorum holds, every agreeing app calls its own `notifier` once for the
  incident. It calls it again on recovery, but only if it was called for the outage.
- **Email, sent once.** The candidates are the agreeing apps that can send email, this
  app included. The first by name sends. If any agreeing report already shows the
  incident as alerted, nobody else sends. If the elected app has not sent within
  `fallback_after`, any other agreeing app that can email sends instead. This can
  occasionally produce two emails, which we prefer to none.
- **Recipients.** The email goes to the contact addresses on the down app's row. A row
  with no contacts gets no email, but the incident is still marked as alerted, so no
  other app sends one either.
- **Recovery.** After `recovery_threshold` good checks in a row (`maintenance` counts as
  good), the incident is resolved. The app that sent the down email sends the recovery
  email. If that app is itself unreachable at that moment, no recovery email is sent.
- **Subjects** carry the peer name and the incident start, so a host that dedupes alerts
  on the exact subject still hears about every incident:
  - `Peerwatch: bravo is down (since 2026-01-05 03:12 UTC)`
  - `Peerwatch: bravo is still down after its maintenance window (since 2026-01-05 03:12 UTC)`
  - `Peerwatch: bravo recovered (down since 2026-01-05 03:12 UTC)`

The `notifier` is called from inside the probe job with one Hash:

```ruby
{
  event:   :down,           # or :recovered
  peer:    "bravo",         # the peer's name, a String
  subject: "Peerwatch: bravo is down (since 2026-01-05 03:12 UTC)",
  body:    "Peer: bravo\nURL: https://bravo.example/up\nDown since: ..."  # the email body text
}
```

Anything the notifier raises is logged and ignored. It runs inside the probe cycle, so
keep it quick; enqueue a job of your own if it has slow work to do.

## Security and trust model

- **One shared token.** Every app in the mesh presents the same token, and whoever holds
  it can read and edit the registry in every app. Editing the registry means choosing
  which URLs and IP addresses your apps will send requests to (with the token attached),
  and which addresses they will email. Treat the token like a credential to every app's
  admin. Keep it in your credentials store, never in source.
- **404 on a bad token.** A missing or wrong token, or no token configured, gets an empty
  404 from both endpoints. Tokens are compared in constant time.
- **Rotation.** There is only one token, so rotate it in every app at once. Until every
  app has the new value, syncing and status reports fail between the apps that differ.
  Probing of health URLs continues, but without status reports, quorum cannot form.
- **HTTPS.** Peer URLs must be `https` unless `allow_http` is set, and the token travels
  in a request header, so serve every app over HTTPS.
- **The registry holds contact email addresses.** The registry endpoint returns them to
  any caller with the token, and the admin pages show them to whoever your
  `admin_parent_controller` lets in.
- **Admin pages.** They are only as private as `admin_parent_controller` makes them. The
  default, `ApplicationController`, is usually not admin-only, so change it.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Limitations

- **Nothing outside the mesh watches the mesh.** If every app goes down together (one
  provider, one region, one DNS service), nobody is left to send the email. Pair
  Peerwatch with an outside monitor if that matters.
- **Quorum needs a second observer that can still answer.** In a mesh of three, if two
  apps go down together, the survivor sees no agreeing report and stays quiet.
- **A two-app mesh cannot tell its own isolation from a peer's outage.** It alerts anyway.
- **The health URL only proves what it checks.** Rails' `/up` shows only that the app
  booted; it does not touch the database. A peer can be broken in ways its health URL
  does not see.
- **One HTTP URL per app.** There are no browser flows, no content checks, no latency
  alerts, and no checks of anything that does not run Peerwatch.
- **The mount path is fixed at `/peerwatch`**, without `as:`, because the other apps
  call `/peerwatch/status` and `/peerwatch/registry`.
- **Last write wins, by each app's own clock.** Registry edits made in two apps at nearly
  the same time resolve by timestamp, so the apps' clocks need to be roughly in sync.
- **Duplicate down emails are possible in a narrow race:** when the fallback sender acts
  before it has seen the elected sender's alert, or when one probe cycle runs into the
  next. Requests in a cycle go one peer at a time, and a peer that is slow to fail can
  take several times `open_timeout + read_timeout`. With many such peers, a cycle can
  outlast the two-minute schedule.
- **Alert channels are email plus one callback.** There is no SMS, phone or escalation.
- **The admin views assume Bootstrap 5 classes and a host layout.** They bring no CSS of
  their own, and they don't render flash messages; your layout is expected to.
- **History is kept by name.** Checks and incidents belong to a peer's name, so a removed
  peer that is restored, or a new app given a removed app's name, inherits that history.
- **The dashboard needs a shared cache.** The other observers' columns on the dashboard,
  and the "Observers agreeing" line in the down email, come from `Rails.cache`. The cache
  must therefore be shared between the process that runs jobs and the one that serves
  pages or sends mail (Solid Cache, Redis or similar). The decision to alert does not
  depend on the cache.
- **Databases.** It is tested on SQLite and PostgreSQL. MySQL and MariaDB are untested.

## Development, contributing, security, licence

- Development and contributing: [CONTRIBUTING.md](CONTRIBUTING.md). In short,
  `bin/setup`, then `bundle exec rake` runs the specs and RuboCop.
- Changes: [CHANGELOG.md](CHANGELOG.md).
- Reporting a vulnerability: [SECURITY.md](SECURITY.md).
- Licence: MIT, see [MIT-LICENSE](MIT-LICENSE).
