# Contributing

Thank you for helping. Bug reports, documentation fixes and small focused pull requests
are all welcome. For anything larger, please open an issue first so we can agree on the
approach before you spend time on it.

## Setting up

You need Ruby 3.2 or newer.

```sh
bin/setup            # bundle install
```

`Gemfile.lock` is not committed: a gem is tested against fresh resolutions, the way its
users install it.

## Running the specs

```sh
bin/test                      # all specs; same as bundle exec rspec
bin/test spec/lib/evaluator_spec.rb
bundle exec rake              # specs, then RuboCop (what CI runs, plus the lint job)
```

The specs run against a small host app in `spec/dummy`. By default it uses SQLite in
memory, and the specs make no network calls (WebMock blocks them).

To run them against PostgreSQL, install the optional `postgres` group and point
`DATABASE_URL` at a database you have created for the purpose. The suite drops and
recreates the three `peerwatch_*` tables in it at the start of every run.

```sh
bundle config set --local with postgres
bundle install
createdb peerwatch_test
DATABASE_URL=postgres://localhost/peerwatch_test bin/test
```

To test against Rails 8.0 rather than the newest Rails, set `RAILS_VERSION` and let
Bundler resolve again (the lockfile is ignored, so delete it first):

```sh
rm Gemfile.lock
RAILS_VERSION=8.0 bundle install
RAILS_VERSION=8.0 bin/test
```

CI runs Ruby 3.2, 3.3 and 3.4 against Rails 8.0 and 8.1 on SQLite, Ruby 3.4 with Rails 8.1
on PostgreSQL, and RuboCop.

## Style

RuboCop with the [Rails Omakase](https://github.com/rails/rubocop-rails-omakase) rules:

```sh
bundle exec rubocop
```

## Design constraints

A change must keep these true. Most of them have a spec that fails if they break.

- **Never raise out of a job.** Peerwatch runs inside someone else's app, and an exception
  that reaches the host's error reporting becomes an incident of its own. Wrap work in
  `Peerwatch.quietly("context") { ... }`, which logs and swallows.
- **Standard-library HTTP only.** Outbound requests use `Net::HTTP`. The only runtime
  dependency is `rails`; please do not add another.
- **No inline script or style in the views**, and no `on*=` handlers or `javascript:`
  URLs. Hosts may enforce a strict Content Security Policy; `spec/lib/views_csp_spec.rb`
  checks this.
- **Placeholders only.** Names, URLs and addresses in code, specs and docs are
  placeholders such as `alpha`, `bravo`, `https://alpha.example` and `ops@example.com`.
  Never a real site, domain, IP address, email address or person.
- **No outbound requests while rendering a page.** The dashboard reads the database and
  `Rails.cache` only.
- **Small and plain.** Please do not add a feature for a single hypothetical use. If a
  setting or option is needed, it goes in `lib/peerwatch/configuration.rb`, the generated
  initializer template and the configuration table in the README, together.

If a change affects users, add a line under the Unreleased heading in `CHANGELOG.md`.

## Releasing

For the maintainer.

1. Update `Peerwatch::VERSION` in `lib/peerwatch/version.rb`.
2. In `CHANGELOG.md`, replace "Unreleased" with the version and today's date.
3. Run `bundle exec rake` and make sure CI is green on the main branch.
4. Commit, then tag: `git tag -a v0.1.0 -m "v0.1.0"` and `git push origin main v0.1.0`.
5. Build the gem and check what goes into it:

   ```sh
   gem build peerwatch.gemspec
   tar -xOf peerwatch-0.1.0.gem data.tar.gz | tar -tz
   ```

6. Push it. The gemspec sets `rubygems_mfa_required`, so RubyGems asks for your
   one-time code:

   ```sh
   gem push peerwatch-0.1.0.gem
   ```

7. Delete the built `.gem` file, and create a GitHub release for the tag with the
   CHANGELOG entry as its notes.
