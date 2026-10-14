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
| [`pixi-upgrade.yml`](.github/workflows/pixi-upgrade.yml) | Upgrade every dependency in a root `pixi.toml` to its newest version, re-pin each exactly, re-solve `pixi.lock`, and open a pull request. Dependabot for pixi. |

Files prefixed with an underscore (`_release-please.yml`, `_sonarcloud.yml`,
`_test-pixi-upgrade.yml`) are this repository's own CI. They are not callable and never
appear in the table above.

### `pixi-upgrade.yml`

Dependabot has no pixi ecosystem, so a pixi workspace gets no dependency PRs on its own.
This runs `pixi upgrade --pinning-strategy exact-version`, which finds newer versions,
rewrites each pin it moves as an exact `==x.y.z`, and re-solves `pixi.lock`. If anything
moved, it opens one pull request on `deps/update-pixi`, titled the way Dependabot titles
its own (`deps: bump <name> from X to Y`, or `deps: bump the pixi group with N updates`)
and labelled `dependencies`. A later run updates that pull request in place rather than
opening a second one.

There are no inputs. The schedule lives with the caller, because a reusable workflow
cannot carry its own `schedule:`:

```yaml
name: Update pixi dependencies

on:
  schedule:
    - cron: '0 6 * * 1' # Mondays 06:00 UTC
  workflow_dispatch:

permissions:
  contents: read

jobs:
  pixi-upgrade:
    uses: TomBorglum/workflows/.github/workflows/pixi-upgrade.yml@v1
    secrets:
      AUTOMATION_APP_CLIENT_ID: ${{ secrets.AUTOMATION_APP_CLIENT_ID }}
      AUTOMATION_APP_PRIVATE_KEY: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

**It fails if there is no `pixi.toml` in the repository root.** That is deliberate, and
it is not the same as "no pixi workspace": pixi also reads a manifest embedded in
`pyproject.toml` under `[tool.pixi.workspace]`, and would silently upgrade that instead.
Only a root `pixi.toml` is accepted.

**Both secrets are required**, and they must belong to a GitHub App installed on the
calling repository with **Contents**, **Pull requests** and **Issues** set to read/write.
Issues is the easily-missed one — the `dependencies` label is applied through the issues
API. A GitHub App rather than `GITHUB_TOKEN` because events created by `GITHUB_TOKEN` do
not trigger further workflow runs, so the pull request would never run your required
status checks and could never merge.

**All dependencies are assumed to be exactly pinned already.** `--pinning-strategy`
governs the pins pixi *writes*, so a dependency already sitting at its newest version
keeps whatever constraint it has. This workflow does not tighten a manifest that starts
out loosely pinned.

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
