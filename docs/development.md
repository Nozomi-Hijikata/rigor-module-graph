# Development

Local setup, git hooks, CI / Release workflows, and what the
test suite covers. The forward-looking design notes live in
[the design plan](plan.md); known rough edges live in
[the limitations doc](limitation.md).

## Local setup

```sh
bundle install
bundle exec lefthook install      # wire pre-commit / pre-push hooks
bundle exec rake test
UPDATE_SNAPSHOTS=1 bundle exec rake test   # to refresh snapshots
bundle exec rake coverage         # C2 (branch) coverage report under ./coverage
```

## Git hooks

`lefthook.yml` wires five checks. The split is "fast on every
commit, full suite on push":

| hook       | command       | scope                                    |
|------------|---------------|------------------------------------------|
| pre-commit | rubocop       | whole project (`bundle exec rubocop --parallel`) |
| pre-commit | betterleaks   | staged content, secret scan              |
| pre-commit | rigor check   | whole `lib/` (`bundle exec rigor check lib`) |
| pre-commit | zizmor        | staged GitHub Actions workflow files     |
| pre-push   | minitest      | full `rake test`                         |

The pre-commit checks run in parallel; on this repo they finish
in ~1 second together. `betterleaks` (`brew install betterleaks`
on macOS) and `zizmor` (`brew install zizmor` or `pipx install
zizmor`) are external binaries — the others come in through
Bundler. `rubocop` re-stages autocorrected files. `zizmor` is
gated on workflow files only so day-to-day commits don't trigger
it.

`rubocop` and `rigor` scan the whole project rather than just
the staged files so the local hook catches the same kind of
unstaged drift CI does (an old `Gemfile` lint violation, a
`Rakefile` magic-comment cop firing only at the project level).

Skip a hook ad-hoc with `LEFTHOOK_EXCLUDE=<command>` — e.g.
`LEFTHOOK_EXCLUDE=rigor git commit ...`.

## CI / Release workflows

Four GitHub Actions workflows under `.github/workflows/`. Every
action is SHA-pinned; a SHA-pinning policy is enforced both via
zizmor in CI and via the repo's "Allow specified actions"
setting.

### `ci.yml` — push and PR to `main`

- **`test`** — minitest, then minitest with C2 coverage
  (`COVERAGE=1`), uploads `coverage/` as a build artefact
  retained for 14 days.
- **`lint`** — RuboCop in `--parallel` mode, then
  `rigor check lib`.
- **`workflow-lint`** — zizmor audits the workflow files
  themselves. Runs with `security-events: write` so findings
  surface in the repo's Security tab.

All jobs cache the bundler install keyed on `Gemfile.lock` and
set `persist-credentials: false` on `actions/checkout`.

### `docs.yml` — push to `main`

Generates RDoc via `bundle exec rake rdoc` and deploys `doc/`
to GitHub Pages. The live site is at
[nozomemein.github.io/rigor-module-graph](https://nozomemein.github.io/rigor-module-graph/).
Single-flight concurrency on the `pages` group so two quick
merges don't race.

### `release.yml` — manual trigger

`workflow_dispatch`-only. The flow:

1. Reads `VERSION` from `lib/rigor/module_graph/version.rb`
2. Greps `CHANGELOG.md` for a matching `## [VERSION]` heading —
   fails with a clear error if missing
3. Runs the test suite
4. Builds the gem and uploads it as an artefact
5. Pushes to RubyGems via
   [trusted publishing](https://guides.rubygems.org/trusted-publishing/)
   — OIDC, no long-lived API key

A `dry_run: true` input runs the build / test / unpack steps
without the final push, useful for rehearsing pipeline changes.

The `rubygems` GitHub Environment binding lets the gem's
rubygems.org Trusted Publisher accept tokens from this workflow
specifically.

### `purge-readme.yml` — push to `main`

GitHub renders README images through
`camo.githubusercontent.com`, which keeps a ~24h independent
cache. This workflow scrapes camo URLs from the rendered repo
page and sends HTTP `PURGE` to each, so updated images take
effect in line with the commit instead of when the camo cache
naturally expires.

## Test suite

The test suite covers:

- `ConstantName`, `Edge`, `Analyzer`, `CycleDetector`,
  `ZeitwerkResolver`, `Reachability`, `Stats`, `Inflector`,
  `VisibilityMap` as unit tests.
- `Dot`, `Mermaid`, `Uml::ClassDiagram` rendering via
  `minitest-snapshot`.
- An integration test that boots the real `rigor` binary
  against `test/fixtures/rails_app/` and snapshots the
  `edges.jsonl` output.

Snapshots refresh with `UPDATE_SNAPSHOTS=1`. C2 (branch)
coverage runs with `COVERAGE=1` or `rake coverage`; the
baseline is around 91%.
