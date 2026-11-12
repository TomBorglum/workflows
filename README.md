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
| [`docker-hub-publish.yml`](#docker-hub-publish) | Build, scan, sign and publish one container image per directory declared in a config file to Docker Hub, plus an OCI compose artifact per compose project, using GitHub OIDC and AWS to reach a Docker Hub credential. |
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

### docker-hub-publish

Builds one container image per directory a config file declares, fails the release on a HIGH
or CRITICAL Trivy finding, publishes each image to Docker Hub with `regctl`, signs every
published digest with `cosign`, and publishes each compose directory as an OCI compose
artifact. Scan suppressions are declared per image, not per run.

Docker Hub supports no OIDC for personal accounts, so the credential is reached through
AWS: the publishing job mints a GitHub OIDC token, assumes an IAM role with it, and reads
a Docker Hub PAT out of SSM Parameter Store. **No Docker Hub password or PAT is ever
stored as a GitHub secret.**

The exchange is [`TomBorglum/actions/aws/assume-role`](https://github.com/TomBorglum/actions/tree/main/aws/assume-role),
called at a pinned commit SHA. A composite action appears in no OIDC claim, so the trust
policy a caller puts on the role is unaffected by it.

[`docs/docker-hub-publish.md`](docs/docker-hub-publish.md) is the full reference: what a
caller must provide, what fails a release, the AWS objects to create and the trust policy
to put on the role.

```yaml
name: Publish

on:
  release:
    types: [published]
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read

# Declared HERE, not in the called workflow: GitHub cancels the caller when the two share
# a group, and a release must never be cancelled partway through publishing.
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  images:
    uses: TomBorglum/workflows/.github/workflows/docker-hub-publish.yml@v2.0.0
    permissions:
      contents: read
      id-token: write
    with:
      # Optional. Defaults to .github/docker-hub-publish.yml.
      # config: .github/docker-hub-publish.yml
      aws-region: ${{ vars.AWS_REGION }}
      aws-ssm-parameter: /my-project/release/dockerhub-pat
      dockerhub-namespace: ${{ vars.DOCKERHUB_NAMESPACE }}
    secrets:
      aws-role-arn: ${{ secrets.AWS_RELEASE_ROLE_ARN }}
```

**Pin an exact `@v1.2.3`, not `@v1`.** The IAM trust policy matches the called workflow's
`job_workflow_ref`, and the recommended pattern admits only immutable exact versions, so a
`@v1` pin cannot assume the role. This is the one workflow here where the moving tag is
the wrong choice.

#### Requirements

Everything the publishing job touches in AWS has to exist first, and the role's trust
policy is what denies every other repository. `docs/docker-hub-publish.md` walks it;
in outline:

- An **IAM role** whose trust policy matches *both* the calling repository's `sub` claim
  and this workflow's `job_workflow_ref` claim. Either alone is insufficient — this
  repository is public, so `job_workflow_ref` on its own would let anyone reach your role.
- An **SSM SecureString** holding a Docker Hub PAT with Read & Write, and an inline policy
  granting `ssm:GetParameter` on that one parameter ARN as a literal.
- **`id-token: write`** on the calling job, as above.
- A **config file** declaring what the repository publishes, `.github/docker-hub-publish.yml`
  by default.
- Per image directory, a **`Dockerfile`** and a **`docker-bake.hcl` declaring
  `target "image"`**.
- Per compose directory, a **`compose.yaml` declaring `name: <repository>-<directory>`**,
  with every variable it interpolates carrying a `:?` guard or a `:-` default. No `.env`
  is required.
- **No nested directories** in either collection.

#### Inputs

The inputs describe the **caller's environment**. What the repository contains, and the scan
policy applied to it, live in the config file.

| Input | Default | Description |
| --- | --- | --- |
| `config` | `.github/docker-hub-publish.yml` | Path to the config file, relative to the repository root. |
| `aws-region` | *(required)* | Region the role is assumed in and the PAT parameter is read from. |
| `aws-ssm-parameter` | *(required)* | Absolute SSM path holding the Docker Hub PAT. Not a secret: a path is an address. |
| `dockerhub-namespace` | *(required)* | Docker Hub namespace every image publishes under. Must be the account the PAT belongs to, which nothing checks. |

#### The config file

```yaml
# .github/docker-hub-publish.yml
images:
  gates:
    vulnerability: release
  directories:
    backend:
    frontend:
      trivyignores:
        - .trivyignore.yaml
      vex-documents:
        - frontend.openvex.json
compose-projects:
  stack:
```

| Key | Default | Description |
| --- | --- | --- |
| `images.directories` | *(required)* | Mapping keyed by directory, one key per image. Each directory holds a `Dockerfile` and a `docker-bake.hcl`, and publishes to `<namespace>/<repository>-<directory>`. At least one key. |
| `images.directories.<dir>.trivyignores` | *(none)* | List of `.trivyignore` or `.trivyignore.yaml` files, **one file per element**, applied to this image's scan alone. |
| `images.directories.<dir>.vex-documents` | *(none)* | List of OpenVEX documents, one file per element, reaching Trivy as `--vex` for this image alone. A `not_affected` or `fixed` statement suppresses its finding; `affected` and `under_investigation` do not. |
| `images.gates.vulnerability` | `always` | Which caller events a HIGH or CRITICAL finding fails. `always` fails every event; `release` fails a release and reports to the job summary on a `pull_request`. The separate wrong-image check is never relaxed. |
| `compose-projects` | *(none)* | Mapping keyed by directory, one key per OCI compose artifact, following the same name formula. Omitted by a repository publishing images alone. |

**Suppression paths resolve against the image's own directory**, and a path that is absolute
or contains a `..` component is refused. Two images cannot share one file, so neither keeps a
stale entry masking a regression once the other is fixed.

A directory declared twice is a YAML duplicate-key error, which is why both collections are
mappings rather than lists.

Every key above is validated before any image is built. An absent named file, a directory
missing its `Dockerfile` and an unrecognised gate value each fail the run with a message
naming the problem.

#### Secrets

| Secret | Description |
| --- | --- |
| `aws-role-arn` | The IAM role to assume, as a full ARN. A **secret** rather than an input so the account id inside it is masked — the runner echoes a step's `with:` block before the action runs. A bare role name is rejected. |

The workflow declares **no outputs**. What crosses the boundary is what it publishes.

#### What it does not do

Publishing happens only on a `release` event — the job holding the credential carries
`if: github.event_name == 'release'`. On a pull request the images are still built,
scanned and gated and the compose files still validated, so a change that breaks the
release is caught before the tag exists.

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

`docker-hub-publish` is the exception to that table: pin it to an exact `@v1.2.3`,
because the AWS trust policy its callers need admits only immutable version tags. See
[its section](#docker-hub-publish).

`v1` and `v1.2` are deliberately mutable — that is how a fix reaches you without
your intervention. A tag ruleset covers every `v*` tag, restricting creation, deletion
and force pushes with the release automation as its only bypass actor, so a moving tag
moves only when a release moves it and an exact version never moves at all. `@v1.2.3`
and `@<sha>` are equally safe pins.

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
including for maintainers.

Version tags are governed by two tag rulesets. `version-tags` covers `refs/tags/v*` and
restricts creations, updates, deletions and force pushes, with the release App as its only
bypass actor, so no human creates or moves a version tag. `released-versions` covers
`refs/tags/v*.*.*` and restricts updates, deletions and force pushes with **no** bypass
actor, so an exact version that exists cannot be moved or deleted by anyone, the App
included. That second ruleset is what the AWS trust policy's `v*.*.*` condition rests on;
[`docs/docker-hub-publish.md`](docs/docker-hub-publish.md) explains why both are needed.

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
