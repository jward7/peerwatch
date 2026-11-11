# Installing Peerwatch

This guide takes you from nothing to a working mesh: first the first app, then each
further app, then a checklist to confirm it works. You should not need to read the code
to follow it. The examples use the placeholder apps `alpha` (the first app) and `bravo`
(the second), at `https://alpha.example` and `https://bravo.example`.

- [1. Prerequisites](#1-prerequisites)
- [2. Install the first app](#2-install-the-first-app)
- [3. Join each further app](#3-join-each-further-app)
- [4. Verify](#4-verify)
- [5. What commonly blocks the endpoints](#5-what-commonly-blocks-the-endpoints)
- [6. A staging app with a mail catcher](#6-a-staging-app-with-a-mail-catcher)
- [7. Uninstalling](#7-uninstalling)

## 1. Prerequisites

Each app needs all of the following.

- **Rails 8.0 or newer and Ruby 3.2 or newer.** Peerwatch is tested on Rails 8.0 and 8.1
  with SQLite and PostgreSQL. MySQL and MariaDB are untested.
- **An Active Job backend that runs recurring jobs**, such as Solid Queue (the Rails 8
  default), and that actually runs in the environment you are installing in.
- **Mail that works.** Alerts are sent through Action Mailer with `deliver_later`, using a
  mailer class of yours as the parent, so your From address, delivery settings and
  interceptors apply.
- **HTTPS with a certificate that verifies.** Peer URLs must be `https`, and certificates
  are verified, so a self-signed certificate counts as a failure.
- **A health URL that answers 2xx without passing through your authentication, maintenance
  mode or rate limiting.** Rails' built-in `/up` skips your controllers' filters, but Rack
  middleware still applies to it; see [section 5](#5-what-commonly-blocks-the-endpoints).
  Redirects count as down, so the URL must answer directly.
- **A cache shared between your job process and your web process** (Solid Cache, Redis or
  similar) if you want the dashboard to show the other apps' views. Alert decisions do
  not depend on it, but the dashboard's observer columns do. A per-process cache such
  as `:memory_store` works only when jobs run inside the web process; otherwise those
  columns read "no data".
- **At least two apps, ideally on different servers or providers.** Apps that share a
  server fail together.

## 2. Install the first app

### 2.1 Add the gem

Until the gem is published to RubyGems, install it from a git tag:

```ruby
# Gemfile
gem "peerwatch", git: "https://github.com/jward7/peerwatch", tag: "v0.1.0"
```

Once it is released, use the RubyGems version instead:

```ruby
gem "peerwatch", "~> 0.1.0"
```

Then:

```sh
bundle install
bin/rails g peerwatch:install
```

The generator writes `config/initializers/peerwatch.rb`, which lists every setting with a
comment and its default, and prints the remaining steps.

### 2.2 Generate and store the token

Every app in the mesh shares one secret token. Generate it once:

```sh
bin/rails secret
```

Store the same value in every app's credentials (`bin/rails credentials:edit`, or the
environment-specific file you use for production):

```yaml
peerwatch:
  token: <the value from bin/rails secret>
```

Whoever holds the token can edit the registry in every app, so treat it like an admin
password. See [Security and trust model](../README.md#security-and-trust-model).

### 2.3 Configure the initializer

Here is a worked example for a typical app, with every setting. The timeouts, thresholds
and the settings after them are shown at their defaults. The full list, with defaults,
is in the README's [configuration reference](../README.md#configuration-reference).

```ruby
# config/initializers/peerwatch.rb
Peerwatch.configure do |config|
  # This app's name in the registry: lowercase letters, digits, - and _.
  # It must match this app's row on the peers page.
  config.self_name = "alpha"

  # The shared secret. Blank turns off the API endpoints and all syncing.
  config.token = Rails.application.credentials.dig(:peerwatch, :token)

  # Only on an app joining an existing mesh: any app already in it (see section 3).
  # config.seed_url = "https://bravo.example"

  # The admin pages inherit this controller, so its authentication applies, and render
  # in this layout. See below.
  config.admin_parent_controller = "Admin::BaseController"
  config.layout = "admin"

  # The alert mailer inherits this, so your From address and interceptors apply.
  config.mailer_parent = "ApplicationMailer"

  # False for an app whose mail reaches nobody. It still observes and votes.
  config.can_email = true

  # Called once per down and recovery event. See below.
  config.notifier = ->(event) { OpsAlertJob.perform_later(event[:subject], event[:body]) }

  config.queue_name = :default          # the queue for Peerwatch's two jobs
  config.open_timeout = 5               # seconds to connect, per request
  config.read_timeout = 5               # seconds to wait for an answer, per request
  config.failure_threshold = 2          # failed checks in a row before a peer is down
  config.recovery_threshold = 2         # good checks in a row before it has recovered
  config.fallback_after = 8 * 60        # seconds before another app sends the email instead
  config.retention_days = 30            # days of checks to keep
  config.allow_http = false             # true only for local testing over plain http
end
```

**`admin_parent_controller`.** Peerwatch's admin pages, the dashboard at `/peerwatch` and
the peers page at `/peerwatch/peers`, inherit the controller you name here. They are
exactly as private as that controller makes them. The default, `ApplicationController`,
is usually not limited to admins, so point it at a controller that is. For example:

```ruby
# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    # Replace with however your app decides who is an admin.
    def require_admin
      redirect_to root_path unless current_user&.admin?
    end
  end
end
```

Your controller's route helpers (`root_path` above, a sign-in redirect, the links in your
layout) keep working inside Peerwatch's pages. `config.layout` replaces the parent
controller's layout, so set it to your admin layout. The views use Bootstrap 5 classes
and bring no CSS of their own. They don't render flash messages, so your layout should;
most layouts already do.

**`mailer_parent`.** Name your own mailer, usually `"ApplicationMailer"`, so its
`default from:` and any interceptors apply to alert mail. Both this and
`admin_parent_controller` are read once, when Peerwatch's classes load, so set them in
this initializer and nowhere else.

**`notifier`.** An optional callable for your own alert channel, alongside email. It
receives a Hash with `event` (`:down` or `:recovered`), `peer` (the peer's name),
`subject` and `body` (the email's subject and body text). Every app that agrees a peer is
down calls its own notifier once, and once more on recovery. It runs inside the probe
job, and anything it raises is logged and ignored. If it does slow work, such as calling
another service, have it enqueue a job of your own, as in the example above
(`OpsAlertJob` stands for a job in your app).

### 2.4 Run the migrations

```sh
bin/rails peerwatch:install:migrations
bin/rails db:migrate
```

This copies one migration into `db/migrate`. It creates three tables: `peerwatch_peers`
(the registry), `peerwatch_checks` and `peerwatch_incidents`. Checks are deleted after
`retention_days`. As a guide to size, an app watching nine others writes about 6,500
check rows a day, so it holds about 195,000 at the default 30 days.

### 2.5 Mount the engine

```ruby
# config/routes.rb
mount Peerwatch::Engine, at: "/peerwatch"
```

Mount it at exactly `/peerwatch`, and do not pass `as:`. The other apps call
`/peerwatch/status` and `/peerwatch/registry` on that path, and Peerwatch's pages find
their own routes through the default `peerwatch` route helper.

Mount it **outside** any `authenticate`, `constraints` or admin-only block in your
routes. The other apps call the two API endpoints with the token and no session. Inside
such a block they would get a redirect or a 404 instead of an answer, and would count
your app as unreachable. The admin pages are still protected, by
`admin_parent_controller`.

### 2.6 Schedule the probe

`Peerwatch::ProbeJob` must run every two minutes. With Solid Queue, add it to
`config/recurring.yml`:

```yaml
# config/recurring.yml
production:
  peerwatch_probe:
    class: Peerwatch::ProbeJob
    schedule: every 2 minutes
```

Solid Queue reads the entries under the key for the current environment. An app that
runs under another environment name, such as a staging app with `RAILS_ENV=staging`,
needs the entry under that key as well:

```yaml
staging:
  peerwatch_probe:
    class: Peerwatch::ProbeJob
    schedule: every 2 minutes
```

With another backend, use its own recurring-job feature to enqueue
`Peerwatch::ProbeJob` every two minutes:

- **GoodJob:** its cron feature (`config.good_job.cron`); see the GoodJob docs.
- **Sidekiq:** a scheduling extension such as sidekiq-cron, or Sidekiq Enterprise's
  periodic jobs; see their docs.
- **Plain cron or a systemd timer:** run
  `bin/rails runner "Peerwatch::ProbeJob.perform_later"` every two minutes.

The job does nothing until `self_name` is set, and it never raises. Problems are logged
as lines starting with `[Peerwatch]`.

### 2.7 Add a nav link

In your admin layout or menu:

```erb
<%= link_to "Peerwatch", peerwatch.dashboard_path %>
```

### 2.8 Create the peer rows

Deploy, sign in as an admin and open `/peerwatch/peers`.

1. **Add this app's own row first.** Its name must equal `self_name` (`alpha`). Base URL
   `https://alpha.example`, health path `/up`, and the contact emails that should hear
   when *this* app is down.
2. **Add a row for each other app** you will install Peerwatch in (`bravo`, and so on),
   with the name each of them will use as `self_name`.

The fields are:

- **Name**: lowercase letters, digits, `-` and `_`. It cannot be changed later, because it
  is the key every app syncs on.
- **Base URL**: the app's public `https` URL, using the hostname the app itself accepts.
- **Health path**: default `/up`. Point it at a deeper check if you have one, such as
  a page from a health-check gem that also tests the database.
- **IP address** (optional): when a check fails, Peerwatch retries once against this
  address, keeping the hostname for TLS, to tell a DNS failure from an app failure.
- **Environment** (optional): shown on the dashboard.
- **Contact emails**: one per line or comma-separated. They are emailed when this app is
  down and when it recovers.
- **Maintenance until / note**: a declared maintenance window; see
  [Maintenance windows](../README.md#maintenance-windows).

Each save is pushed to the other apps straight away and repaired on every probe cycle.
Removing a peer keeps a tombstone so the removal syncs too. To restore a removed peer,
add a peer with the same name.

## 3. Join each further app

For `bravo`, and each app after it:

1. Follow sections [2.1](#21-add-the-gem) to [2.7](#27-add-a-nav-link) with the same token.
2. Set `self_name` to the name the first app gave this app's row (`"bravo"`).
3. Set `seed_url` to any app already in the mesh:

   ```ruby
   config.seed_url = "https://alpha.example"
   ```

4. Deploy. On its first probe cycle, `bravo` finds that it knows no peers yet, pulls the
   whole registry from the seed, and starts probing everyone. From then on it learns of
   changes from every peer. `seed_url` can stay set; it is just one more place to pull
   the registry from.

There is no need to add rows on `bravo`: they arrive from the seed. If `bravo`'s own row
was never added on the first app, add it now on either app's peers page.

## 4. Verify

Run through this list after each install. `alpha.example` is the app being checked.

1. **The dashboard renders.** Open `https://alpha.example/peerwatch` as an admin. Then
   open it signed out, or as a non-admin, and make sure your own access control turns you
   away.
2. **The status endpoint answers with the token.** Read the token into a shell variable
   without echoing it, then call the endpoint:

   ```sh
   read -s PEERWATCH_TOKEN
   curl -i -H "Authorization: Bearer $PEERWATCH_TOKEN" https://alpha.example/peerwatch/status
   ```

   Expect `HTTP/2 200` (or `HTTP/1.1 200`) and JSON that starts with `"name":"alpha"`.
3. **The status endpoint hides itself without the token.**

   ```sh
   curl -i https://alpha.example/peerwatch/status
   ```

   Expect a 404 with an empty body. A redirect, 401, 403 or 429 here means something in
   front of Peerwatch is answering; see [section 5](#5-what-commonly-blocks-the-endpoints).
4. **Checks arrive.** Wait two probe cycles, about four minutes. The dashboard should show
   a "Last checked" time for every other app and a state in this app's column. Once the
   other apps have probed too, their columns fill in.
5. **Maintenance syncs.** On `alpha`, declare a one-minute window:

   ```sh
   bin/rails peerwatch:maintenance MINUTES=1 NOTE="install check"
   ```

   It should print `... 1 of 1 peers accepted it.` (or `N of N`). On `bravo`'s dashboard,
   `alpha`'s row now shows "maintenance until" with the note. The app stays up; the window
   only tells the others not to alert. It ends by itself after a minute, or you can clear
   it with `MINUTES=0`.

If something is missing, look in the logs of both apps for lines starting with
`[Peerwatch]`, and in the access logs for requests with the User-Agent `peerwatch/0.1.0`.

## 5. What commonly blocks the endpoints

Peerwatch's requests reach your app like any other client's: through your proxy, your
Rack middleware and your router. These are the usual obstacles.

| Obstacle | Symptom | What to do |
|---|---|---|
| **Host authorization** (`config.hosts`) | The probe gets a 403, so the app shows as down. | Use the app's canonical hostname as its base URL, the one already in `config.hosts`. If you exclude paths from host authorization, include the health path. |
| **Rate limiters** (Rack::Attack or similar, or a proxy rule) | Intermittent 429s or 403s: flapping checks, gaps in the observer columns. | Every observer sends one health request, one status request and one registry request to each app every two minutes. Allow the health path and `/peerwatch/status` and `/peerwatch/registry` through, or raise their limits. Peerwatch always sends `User-Agent: peerwatch/<version>`, so a rule that rejects blank User-Agents will not trip, but a rule that throttles a whole path prefix might. |
| **Maintenance middleware** | Every maintenance looks like an outage, or never shows as maintenance. | Let the health URL through, and answer `/peerwatch/status` with a 503: that pair is recorded as maintenance. If your maintenance mode blocks the health URL too, declare a window before you turn it on. |
| **A site-wide access gate** (HTTP basic auth, an IP allowlist, an identity-aware proxy) | The probe gets a 401, 403 or a redirect to a login page, which counts as down. | Exempt the health path, `/peerwatch/status` and `/peerwatch/registry`. The admin pages at `/peerwatch` and `/peerwatch/peers` can stay behind the gate. |
| **Forcing SSL** (`config.force_ssl`) | A peer URL entered as `http://` gets a 301, which counts as down. | Use `https` peer URLs, which is the default requirement anyway. Peerwatch does not follow redirects. |
| **Mounting inside an authenticated route block** | The status endpoint redirects to sign-in. | Mount the engine outside it ([2.5](#25-mount-the-engine)). |

## 6. A staging app with a mail catcher

A staging app can join the same mesh as your production apps. If its mail goes to a mail
catcher rather than real inboxes, tell Peerwatch so that it is never elected to send an
alert, which nobody would then receive:

```ruby
config.can_email = false
```

It still probes, reports and votes. That means it counts towards the quorum for the
production apps like any other observer.

Its own row decides who hears when *it* is down. Leave the contact emails empty if
nobody should, and set the environment field to `staging` so the dashboard shows it.
Remember the recurring entry under the `staging:` key if it runs with
`RAILS_ENV=staging` ([2.6](#26-schedule-the-probe)).

## 7. Uninstalling

To take one app out of the mesh:

1. **Remove its row.** On any app's peers page, remove the app's row. The tombstone syncs
   to every app, so they stop probing it and close any open incident for it. Wait one
   probe cycle, then confirm on another app's peers page that it is listed under
   "Removed peers".
2. **Remove Peerwatch from the app.** Delete the recurring entry, the `mount` line, the
   nav link and `config/initializers/peerwatch.rb`, then remove the gem from the
   `Gemfile` and run `bundle install`.
3. **Drop the tables**, if you want the data gone, with a migration of your own:

   ```ruby
   class DropPeerwatchTables < ActiveRecord::Migration[8.0]
     def up
       drop_table :peerwatch_checks
       drop_table :peerwatch_incidents
       drop_table :peerwatch_peers
     end

     def down
       raise ActiveRecord::IrreversibleMigration
     end
   end
   ```

4. **Remove the token** from the app's credentials.

To retire the whole mesh, uninstall every app. There is nothing to remove anywhere else.
