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
- [8. Trying two apps on one machine](#8-trying-two-apps-on-one-machine)
- [9. Upgrading](#9-upgrading)

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
gem "peerwatch", git: "https://github.com/jward7/peerwatch", tag: "v0.2.0"
```

Use the newest tag on the repository's releases page. A git-sourced gem needs `git`
wherever `bundle install` runs, including the build stage of a Docker image (the
Dockerfile Rails generates installs it there).

Once it is released, use the RubyGems version instead:

```ruby
gem "peerwatch", "~> 0.1"
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
and the settings after them are shown at their defaults, except the two allowlists,
which default to `nil` (any) and are shown set, as they should be in production. The
full list, with defaults, is in the README's
[configuration reference](../README.md#configuration-reference).

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
  config.allow_private_addresses = false # true only for local testing against localhost

  # Registry rows come from whoever holds the token, so limit what they can make this
  # app do. A peer URL's host must be one of these (exact, case-insensitive):
  config.allowed_peer_hosts = %w[alpha.example bravo.example]
  # and every contact email must be at one of these domains (exact, case-insensitive):
  config.allowed_contact_domains = %w[example.com]
end
```

**`allowed_peer_hosts` and `allowed_contact_domains`.** Both default to `nil`, meaning
any host and any domain. Set both in every app in production, and keep them the same
across the mesh: an app refuses a row that breaks its lists, so a host missing from one
app's list leaves that app unable to watch it. Adding an app to the mesh then means
adding its hostname to every app's list and deploying them before you add its row. See
[Security and trust model](../README.md#security-and-trust-model) for what the lists
protect against and what they do not.

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
most layouts already do. To fit the pages into your breadcrumbs and nav, or to restyle
them, see [Making it look native](#making-it-look-native).

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

Two things in a host app can trip over the jobs:

- **A deploy guard that waits for imminent recurring jobs.** If your deploy script refuses
  to proceed while a recurring job is due soon, exempt `Peerwatch::ProbeJob` and
  `Peerwatch::PushJob`. A job that runs every two minutes is always due soon, so
  otherwise every deploy is blocked. Skipping one probe cycle during a deploy is harmless.
- **Specs that expect every job to inherit `ApplicationJob`.** Both Peerwatch jobs inherit
  `ActiveJob::Base`, because an engine cannot depend on the host's `ApplicationJob`. A
  spec asserting that every class in `config/recurring.yml` is `< ApplicationJob` needs
  to allow classes in the `Peerwatch::` namespace, or check `< ActiveJob::Base` instead.

### 2.7 Add a nav link and make it look native

In your admin layout or menu:

```erb
<%= link_to "Peerwatch", peerwatch.dashboard_path %>
```

#### Making it look native

Peerwatch's pages are meant to be a blank canvas inside your admin. Out of the box:

- **They render in your layout** (`config.layout`), behind your admin controller
  (`admin_parent_controller`), so your navbar, sidebar, sign-in and flash messages are
  all yours.
- **Your links work.** Your app's route helpers, including ones that share a name with
  a Peerwatch route such as `dashboard_path`, resolve to your routes inside Peerwatch's
  pages. Reach Peerwatch's own routes through `peerwatch.`, as in
  `peerwatch.dashboard_path` and `peerwatch.mesh_peers_path`.
- **They leave layout and spacing to you.** Each page is a single
  `<div class="peerwatch peerwatch-...">` with no container or padding of its own, so it
  sits in your content area like any other admin page. The two classes are there for
  scoping your own CSS.
- **They set the page title.** Each page sets `content_for(:title)` (for example
  `Peerwatch · Peers`) unless something already set it, so a layout that reads
  `content_for(:title)` shows the right title.
- **They use plain Bootstrap 5 classes** and ship no CSS or JavaScript.

**Breadcrumbs and the active nav item.** Every page renders the partial
`peerwatch/_page_chrome`, which renders nothing until you override it. Copy it into your
app:

```sh
bin/rails g peerwatch:views -v chrome
```

It receives three locals:

| Local | Example |
|---|---|
| `section` | `:dashboard` or `:peers` |
| `title` | `"Peerwatch · Peers · Add a peer"` |
| `crumbs` | `[["Peerwatch", "/peerwatch/"], ["Peers", "/peerwatch/peers"], ["Add a peer", nil]]` (the last one has no link) |

For a layout that shows `content_for(:breadcrumbs)` in a Bootstrap breadcrumb bar:

```erb
<%# app/views/peerwatch/_page_chrome.html.erb %>
<% content_for :breadcrumbs do %>
  <% crumbs.each do |label, path| %>
    <li class="breadcrumb-item"><%= path ? link_to(label, path) : label %></li>
  <% end %>
<% end %>
```

The same partial in Slim, with your own admin home as the first crumb:

```slim
/ app/views/peerwatch/_page_chrome.html.slim
- content_for :breadcrumbs do
  li.breadcrumb-item = link_to "Admin", main_app.admin_root_path
  - crumbs.each do |label, path|
    li.breadcrumb-item = path ? link_to(label, path) : label
```

The partial can set anything else your layout reads, such as a `content_for` that
collapses a sidebar. Keep it free of output that should appear in the page body: it is
rendered at the top of the page.

To mark your Peerwatch nav item active, check the controller path in your layout or
menu. It is `peerwatch/dashboard` or `peerwatch/peers` on Peerwatch's pages:

```erb
<%= link_to "Peerwatch", peerwatch.dashboard_path,
      class: ["nav-link", ("active" if controller_path.start_with?("peerwatch/"))] %>
```

Checking the path works as well, as long as it matches where you mounted the engine:
`request.path.start_with?("/peerwatch")`. Don't test `controller_name == "dashboard"`:
Peerwatch's dashboard controller has that name too, so your own Dashboard item would
light up on Peerwatch's page.

**Changing the pages themselves.** Copy the views into your app, as with
`devise:views`:

```sh
bin/rails g peerwatch:views                  # everything
bin/rails g peerwatch:views -v dashboard     # one or more groups
```

The groups are `chrome`, `dashboard`, `peers` and `mailer`. Your copies in
`app/views/peerwatch/` take precedence over the gem's, so you can restyle them, swap
Bootstrap classes for your own, or convert them to Slim or Haml (delete the `.erb` copy
when you do). The pages are split into small partials, such as
`dashboard/_matrix`, `dashboard/_state_badge`, `peers/_table` and `peers/_form`, so you
can usually copy one partial rather than a whole page.

Delete every copied file you don't change. A copy no longer follows the gem, so after
upgrading Peerwatch, compare your copies with the new ones (rerun the generator into a
scratch branch and diff) and read the CHANGELOG for view changes.

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
  address, keeping the hostname for TLS, to tell a DNS failure from an app failure. It
  must be a public address.
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

1. Follow sections [2.1](#21-add-the-gem) to [2.7](#27-add-a-nav-link-and-make-it-look-native) with the same token.
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
`[Peerwatch]`, and in the access logs for requests with the User-Agent `peerwatch/<version>`.

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
| **A peer on a private address** (a VPC, VPN or Docker network address, or a name that resolves to one) | The peers page refuses the row, or checks fail with the error class `Peerwatch::Address::NotPublic` and no request is sent. | Use each app's public hostname. Only if the apps can reach each other solely over a private network, set `allow_private_addresses = true`, knowing it removes the protection against requests to internal addresses. |
| **The allowlists** (`allowed_peer_hosts`, `allowed_contact_domains`) | The peers page refuses the row; rows from other apps are skipped with a `[Peerwatch] registry merge: ignored ...` warning; the dashboard marks an existing row "blocked by this app's rules". | Add the host or domain to the lists in every app and deploy. |
| **An egress proxy** (`http_proxy`, `https_proxy`) | Every check fails with a connection error. | Peerwatch ignores proxy settings, because a proxy would resolve peer names itself. Allow direct outbound HTTPS to your peers. |

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

## 8. Trying two apps on one machine

To try Peerwatch before deploying, run two apps locally, for example `alpha` on port
3000 and `bravo` on port 3001, each with its own database and the same token. Peerwatch
refuses plain `http` and refuses to connect to `localhost` or any other non-public
address, so in development only, set both of these in each app:

```ruby
Peerwatch.configure do |config|
  # ...
  config.allow_http = Rails.env.development?
  config.allow_private_addresses = Rails.env.development?
end
```

Then add the rows with base URLs `http://localhost:3000` and `http://localhost:3001`. If
you also set `allowed_peer_hosts` in development, include `localhost` in it. Run the
probe by hand with `bin/rails runner "Peerwatch::ProbeJob.perform_now"` in each app, or
schedule it as in [2.6](#26-schedule-the-probe). Never set either option in production:
together they let anyone with the token make your apps send requests, with the token
attached, to any address your servers can reach.

## 9. Upgrading

Read the [CHANGELOG](../CHANGELOG.md) entries between your version and the new one
first; each lists upgrade notes where a change needs action. Then, in each app:

1. **Bump the tag** in the `Gemfile`, for example `tag: "v0.2.0"`.
2. **Update only Peerwatch:**

   ```sh
   bundle update peerwatch --conservative
   ```

   Without `--conservative`, Bundler also updates every gem Peerwatch depends on, which
   for Peerwatch means Rails and its dependencies. Check that the `Gemfile.lock` diff
   touches only the `peerwatch` entry.
3. **Copy any new migrations** and run them. Most releases have none, and the command
   copies nothing when there is nothing new:

   ```sh
   bin/rails peerwatch:install:migrations
   bin/rails db:migrate
   ```

4. **Compare any views you copied** with `peerwatch:views` against the new ones, if the
   CHANGELOG mentions view changes (see [Making it look native](#making-it-look-native)).
5. **Run your specs and deploy.**

Apps in a mesh can run different Peerwatch versions while you roll an upgrade out, unless
the CHANGELOG says otherwise, so there is no need to deploy them all at once.
