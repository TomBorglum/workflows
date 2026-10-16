# workflows

Reusable GitHub Actions workflows, maintained in one place and released together.

Companion to [TomBorglum/actions](https://github.com/TomBorglum/actions), which
publishes composite *actions* (steps you drop into a job). This repository publishes
reusable *workflows* — whole jobs you call instead of writing.

A reusable workflow is called at the **job** level, not as a step:

```yaml
jobs:
  ci:
    uses: TomBorglum/workflows/.github/workflows/node-ci.yml@v1
    with:
      node-version: "22"
    secrets: inherit
```

## Workflows

| Workflow | Purpose |
| --- | --- |
| [`update-pixi-dependencies.yml`](#update-pixi-dependencies) | Upgrade a [pixi](https://pixi.sh) workspace's dependencies and open a pull request with what moved — the updater Dependabot has no `pixi` ecosystem to provide. |

Files prefixed with an underscore (`_release-please.yml`, `_sonarcloud.yml`) are this
repository's own CI. They are not callable and never appear in the table above.

### update-pixi-dependencies

Upgrades a [pixi](https://pixi.sh) workspace's dependencies — rewriting `pixi.toml` and
`pixi.lock` — and opens a pull request with what moved. **Dependabot has no `pixi`
ecosystem**, so a version declared in a `pixi.toml` is never bumped for you however many
other ecosystems you have covered. Called on a schedule, this is the updater that bumps
it.

It wraps
[`TomBorglum/actions/pixi/upgrade-dependencies`](https://github.com/TomBorglum/actions/tree/main/pixi/upgrade-dependencies),
which performs the upgrade and reports what moved but deliberately opens no pull request.

```yaml
name: Update pixi dependencies

on:
  schedule:
    - cron: '0 6 * * 2' # Tuesdays 06:00 UTC
  workflow_dispatch:

permissions:
  contents: read

jobs:
  update:
    uses: TomBorglum/workflows/.github/workflows/update-pixi-dependencies.yml@v1
    secrets:
      app-client-id: ${{ secrets.AUTOMATION_APP_CLIENT_ID }}
      app-private-key: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

#### Requirements

**Your repository declares its own pixi version in an `.envrc`:**

```bash
use pixi 0.81.0
```

This workflow installs no pixi of its own. It evaluates that `.envrc` with
[`direnv/setup`](https://github.com/TomBorglum/actions/tree/main/direnv/setup), whose
`use pixi <version>` directive installs that exact pixi and puts it on `PATH`. The
resolver that judges your upgrade is therefore the one you already pin for your
workstations and your CI, and there is no pixi version to configure here — or to keep in
step with yours.

Two consequences worth knowing:

- An `.envrc` that uses directives beyond `use pixi`, `use fnm`, `use sdk` and direnv's
  own built-ins must name the extras in `stub-directives`, or activation fails. That is
  how an `.envrc` declaring something meaningful only on a workstation still evaluates on
  a runner.
- If you commit a `pixi.lock`, it has to match your `pixi.toml`. Activation runs
  `pixi install --locked`, which aborts on a discrepancy, so a workspace whose lockfile
  has already drifted must commit a consistent one before this workflow can run.

**A GitHub App** installed on the repository with `Contents: read/write` and
`Pull requests: read/write`, and its Client ID and private key stored as secrets.
Deliberately not `GITHUB_TOKEN`: events created with it do not trigger further workflow
runs, so the resulting pull request would never run your own required checks — and a
dependency bump nothing can check is worse than none. The commit is signed as the App.

Set `dry-run: true` to upgrade and report without opening a pull request. That path needs
neither secret.

#### Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory holding both the `.envrc` and the `pixi.toml`. |
| `pinning-strategy` | `exact-version` | How pixi rewrites each constraint it upgrades. Passed through to `pixi upgrade --pinning-strategy`, which owns the valid values. The default is what makes the pull request a reviewable statement of exactly what moved. |
| `branch` | `deps/pixi` | Branch the pull request is opened from. |
| `base` | *(checked-out branch)* | Branch the pull request targets. A caller triggered by `pull_request` or `release` is in detached HEAD and **must** set this. |
| `stub-directives` | *(none)* | Whitespace-separated directive names to define as no-ops during activation. |
| `dry-run` | `false` | Upgrade and report, but open no pull request. Needs no secrets. |

#### Secrets

| Secret | Description |
| --- | --- |
| `app-client-id` | The App's **Client ID** (App settings → General → Client ID), not the numeric App ID. Required unless `dry-run` is true. |
| `app-private-key` | A private key generated for that same App. Required unless `dry-run` is true. |

Both are declared explicitly rather than inherited, so `secrets: inherit` is not needed
and nothing else in your secret store is exposed to this workflow.

#### Outputs

| Output | Description |
| --- | --- |
| `changed` | `'true'` when `pixi.toml` or `pixi.lock` was rewritten, `'false'` otherwise. |
| `summary` | Markdown table of what moved (package, from, to). Empty when nothing changed. |
| `pull-request-number` | Number of the pull request created or updated. Empty when nothing changed, or on a dry run. |
| `pull-request-url` | URL of that pull request, empty under the same conditions. |

The pull request contains **exactly `pixi.toml` and `pixi.lock`** — the paths to commit
are named explicitly, so the materialised pixi environment that activation leaves in the
checkout cannot be committed with them whatever your `.gitignore` covers. It is titled
`deps: update pixi dependencies`; if your repository releases from Conventional Commits,
that subject cuts a patch release.

## Versioning and pinning

Releases are automated from [Conventional Commits](https://www.conventionalcommits.org/)
by [release-please](https://github.com/googleapis/release-please). Each release
produces three tags:

| Pin | Moves? | Use when |
| --- | --- | --- |
| `@v1` | on every 1.x release | **the default choice** — you want fixes and new features without editing your workflow |
| `@v1.2` | on every 1.2.x release | you want patches only |
| `@v1.2.3` | never | you need a reproducible build |
| `@<sha>` | never | you pin everything by SHA as policy |

`v1` and `v1.2` are deliberately mutable — that is how a fix reaches you without
your intervention. Exact versions are immutable and enforced as such by a repository
ruleset, so `@v1.2.3` and `@<sha>` are equally safe pins.

A major bump means `v1` stops moving. You stay on 1.x until you change the pin to
`@v2`, so a breaking change can never arrive unannounced.

See the [changelog](CHANGELOG.md) for what each release contained, and
[releases](https://github.com/TomBorglum/workflows/releases) for the generated notes.

## Constraints worth knowing before you call one

These are GitHub's, not this repository's, and they shape how it is laid out:

- **The path is fixed.** A reusable workflow is addressed as
  `OWNER/REPO/.github/workflows/FILE@REF`. Subdirectories are not addressable, so
  every workflow here is a flat file in `.github/workflows/` and all of the structure
  lives in the filenames.
- **This repository is public on purpose.** A *public* caller can only call reusable
  workflows in *public* repositories. A private caller can call either.
- **There are no redirects.** GitHub deliberately does not redirect renamed actions
  or reusable workflows — if this repository were renamed, every `uses:` referencing
  it would start failing. The name is permanent.
- **`env` does not cross the boundary**, in either direction. Values go in as
  `inputs` and come back as `outputs`.
- **Nesting is capped** at 10 levels deep, and 50 unique reusable workflows per
  caller file (counting nested trees).

## Guardrails

`main` is protected by a repository ruleset: pull requests only, linear history, no
force-pushes or deletions, and a required SonarCloud check — with no bypass actors,
including for maintainers. Version tags have their own ruleset making them immutable.

Every third-party action used here, in this repository's own CI or inside a published
reusable workflow, is pinned to a full commit SHA; Dependabot keeps those pins fresh,
on a cooldown.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) is the guard rail: commit conventions, which
commit types cut a release, why every Dependabot bump here is `deps:`, the tag and
pinning policy, and the checklist for adding a new workflow.

## Security

Workflows here run inside other people's repositories, often with `secrets: inherit`.
See [SECURITY.md](SECURITY.md) for what is in scope and how to report a vulnerability
privately.

## License

[MIT](LICENSE)
