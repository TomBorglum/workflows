# Contributing

Releases are automated with [release-please](https://github.com/googleapis/release-please).
It reads the commit history on `main`, decides the next version, and maintains a
"chore(main): release X.Y.Z" pull request that updates [`CHANGELOG.md`](CHANGELOG.md)
and the version. Merging that PR tags the version and publishes the GitHub Release.

For that to work, commits must follow [Conventional Commits](https://www.conventionalcommits.org/).
This document is the guard rail for how to name commits and branches so the
automation does the right thing.

Most of it is identical to [TomBorglum/actions](https://github.com/TomBorglum/actions/blob/main/CONTRIBUTING.md).
The one place the two repositories genuinely differ is
[the `deps:`-for-everything rule](#the-deps-for-everything-rule), which exists
because reusable workflows cannot be kept in a directory of their own.

## Commit message format

```
<type>(<optional scope>): <description>

<optional body — what changed and why>

<optional footer — BREAKING CHANGE:, Refs #123, Co-Authored-By:>
```

The first line (the *subject*) is what release-please parses. Keep it lowercase,
in the imperative mood ("add", not "added" or "adds"), with no trailing period,
and ideally under ~72 characters.

Where a change belongs to one workflow, use its filename without the extension as
the scope: `fix(node-ci): quote the node-version input`.

## Types

These are the types configured in [`release-please-config.json`](release-please-config.json).
A type does two independent things: it selects the changelog section the change
appears under, and — because release-please treats any commit in a **visible**
(non-hidden) section as a *releasable unit* — it decides whether the change can
cut a release on its own. We keep only `feat`, `fix`, and `deps` visible, so only
those (plus any breaking change) cut releases; every other type is hidden and
merely rides along.

| Type | Example | Changelog section | Cuts a release? |
| --- | --- | --- | --- |
| `feat` | `feat: add a node-ci workflow` | Features | yes — **minor** (1.1.0) |
| `fix` | `fix(node-ci): pass the cache key through` | Bug Fixes | yes — **patch** (1.0.1) |
| `deps` | `deps: bump actions/checkout to v7.0.1` | Dependencies | yes — **patch** (1.0.1) |
| `perf` | `perf: drop a redundant restore step` | *(hidden)* | no — rides along¹ |
| `revert` | `revert: undo the runner change` | *(hidden)* | no — rides along¹ |
| `docs` | `docs: document the pinning policy` | *(hidden)* | no — rides along¹ |
| `chore` | `chore: tidy workflow comments` | *(hidden)* | no — rides along¹ |
| `ci` | `ci: pin actions by sha` | *(hidden)* | no — rides along¹ |
| `build` `refactor` `style` `test` | `refactor: extract a shared job` | *(hidden)* | no — rides along¹ |

¹ **Rides along**: does not trigger a release on its own and — being hidden —
does not appear in the notes either. A PR containing only ride-along types will
not open a release PR until a `feat`/`fix`/`deps` lands.

> **Visibility = releasability.** If you un-hide a section in
> `release-please-config.json`, commits of that type will start cutting releases.
> That is deliberate for `deps`; be intentional before un-hiding anything else
> (a `docs:`-only change cutting a release is usually noise).

## The `deps:`-for-everything rule

**Every Dependabot bump in this repository is prefixed `deps:` and cuts a patch
release — including bumps that only touch this repository's own CI.** That is
deliberate, and it is the opposite of the sibling `actions` repo. Here is why.

The rule in both repositories is the same: *if a consumer receives the change, it has
to cut a release.* What differs is whether the layout lets Dependabot tell the two
apart.

In `actions`, it does. Each action lives in its own top-level directory, so the bumps
that reach consumers (`<name>/action.yml`) and the bumps that do not
(`.github/workflows/**`) are in different directories, and Dependabot takes one entry
per directory with its own `commit-message.prefix`.

Here, it cannot. GitHub only resolves a reusable workflow at
`OWNER/REPO/.github/workflows/FILE@REF` — subdirectories are not addressable in a
`uses:` reference, and workflows are only discovered in `.github/workflows/` in the
first place. So the workflows this repository *publishes* and the workflows that run
its *own* CI are necessarily in one directory. Dependabot's `github-actions` fetcher
scans a directory as a unit; it has no per-file granularity and no per-group prefix.

So the prefix has to be wrong in one direction or the other:

| Choice | When it's wrong | Cost |
| --- | --- | --- |
| `ci:` | a published workflow's pin is bumped | consumers on `@v1` silently receive changed code, with no release and no changelog entry — **silent** |
| `deps:` | an `_*.yml` CI pin is bumped | a patch release nothing consumer-facing changed in — **visible** |

We take `deps:`. A needless patch release is noise you can see and explain; shipping
unreleased code to other people's workflows is not.

When a release turns out to contain only `_*.yml` bumps, say so in the release notes
rather than editing the prefix. If this becomes frequent enough to be a real problem,
the fix is a Dependabot `ignore` for the two CI-only actions plus manual bumps — not
relabelling, which puts you one mistake away from the silent failure.

The cooldown in [`.github/dependabot.yml`](.github/dependabot.yml) follows from the
same reasoning: a bump here can republish to other people's workflows, so upstream
gets a window to withdraw a bad or compromised release before it ships onward.

> **Prefix `ci:` by hand only for changes Dependabot did not make** — editing
> `_sonarcloud.yml`'s JDK version, adding a step to `_release-please.yml`. Those
> genuinely cannot reach a consumer, because nothing callable lives in those files.

## Breaking changes

A breaking change forces a **major** bump (2.0.0). Mark it either with a `!`
after the type, or with a `BREAKING CHANGE:` footer:

```
feat!: rename the node-version input to node
```

```
feat: rename the node-version input to node

BREAKING CHANGE: `node-version` is now `node`; update callers.
```

Be deliberate here: a major bump means the `v1` tag stops moving, and every consumer
pinned to `@v1` stays on the old code until they edit their workflow to `@v2`. That
is the point of the tag — but it also means a careless `!` strands your users.

For a reusable workflow, all of these are breaking:

- Renaming or removing an `input`, or making an optional input required.
- Renaming or removing an `output`.
- Renaming or removing a named `secret` in `on.workflow_call.secrets`.
- **Renaming the workflow file**, which changes the `uses:` path itself. There are no
  redirects — a renamed file is a hard break for every caller.
- Changing which `permissions` the caller must grant, or requiring a secret that
  callers were not passing before.

Adding an optional input with a default is not breaking. Neither is adding an output.

## Squash merges

Pull requests are **squash-merged**, so the whole branch collapses into a single
commit on `main` whose subject is taken from the **PR title** and whose body is
the branch's own commit messages. Therefore:

> **The PR title must be a valid Conventional Commit.**

A PR titled `Update node workflow` (no type) is invisible to release-please and
will neither appear in the changelog nor bump the version. Title it
`fix: ...` / `feat: ...` instead. That holds however many commits the branch
carries, because `squash_merge_commit_title` is `PR_TITLE`. GitHub's default,
`COMMIT_OR_PR_TITLE`, takes the subject from the *commit* when a branch has
exactly one — so a single sloppy commit subject would quietly cut no release.

The one thing release-please still reads from a squash commit's body is a
`BREAKING CHANGE:` footer. That body is the branch's own commit messages
(`squash_merge_commit_message` is `COMMIT_MESSAGES`), **not** the PR
description, so put the footer in a commit on the branch. A footer written only
in the PR description never reaches `main` and is never parsed.

A squash-merged PR yields exactly one changelog entry: its title. So prefer
**focused PRs** — one logical change, one type. A branch that would produce
several separate entries is two PRs: the `main-protection` ruleset requires
linear history and allows only squash and rebase, so the merge commit that would
have preserved each Conventional Commit individually cannot land.

## Version selection

release-please aggregates **every commit merged since the last release** (across
all PRs, not just one branch) and applies the highest-impact bump:

```
any  feat! / BREAKING CHANGE       →  MAJOR
else any  feat                     →  MINOR
else any  fix / deps               →  PATCH
else only ride-along types         →  no release
   (perf, revert, docs, chore, ci, …)
```

## Tags and the pinning policy

Every release produces three tags, and they are not equivalent:

| Tag | Moves? | For |
| --- | --- | --- |
| `v1.0.0` | never | consumers who want byte-for-byte reproducibility |
| `v1.0` | on every 1.0.x release | patches only |
| `v1` | on every 1.x release | the common case — features and fixes, no breaking changes |

`vX` and `vX.Y` are force-moved by
[`_release-please.yml`](.github/workflows/_release-please.yml) after each release. That
mutability is the published contract: `@v1` is what most consumers should write, and
it is how a security fix reaches them without their intervention.

Exact `vX.Y.Z` tags are immutable, and the `version-tags` repository ruleset enforces
it — `deletion` and `non_fast_forward` over a `v*.*.*` pattern, which needs two
literal dots and so matches `v1.0.0` but neither `v1` nor `v1.0`. Nobody can repoint
a released version, including maintainers; there are no bypass actors.

**This repo pins its own dependencies the other way.** Every third-party action in a
workflow here — published or CI-only — is pinned to a full 40-character commit SHA
with the version in a trailing comment:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

That is not inconsistent with publishing moving tags — it is the same judgement from
both sides. Inbound dependencies we do not control get pinned immutably; outbound
tags we do control are offered as a convenience, with immutable alternatives
alongside. Dependabot updates a SHA pin and its comment together, so keep the comment
accurate.

## Naming workflow files

Because subdirectories are not addressable, the filename is the only structure there
is. It is also part of the public API — renaming a file breaks every caller. So:

```
<domain>-<purpose>.yml

node-ci.yml
node-release.yml
terraform-plan.yml
docker-build-push.yml
```

- **Lowercase kebab-case, `.yml`**, grouped by leading domain so the directory listing
  sorts usefully.
- **Name the job, not the implementation.** `node-ci.yml` survives a move from npm to
  pnpm; `npm-ci.yml` does not.
- **A leading underscore means "this repository's own CI, never callable"** —
  `_release-please.yml`, `_sonarcloud.yml`, `_test-*.yml`. Underscored files sort to
  the top, are excluded from the README table, and are the only files a `ci:`-prefixed
  commit may touch. Nothing with `on: workflow_call` gets an underscore, and nothing
  underscored gets `on: workflow_call`.

## Adding a new reusable workflow

Each workflow is a flat file in `.github/workflows/` and is consumed as
`TomBorglum/workflows/.github/workflows/<name>.yml@v1`. A PR introducing one should
land all of:

- `.github/workflows/<name>.yml`, with `on: workflow_call` declaring every `input`,
  `secret` and `output` explicitly — no `secrets: inherit` on the *callee* side — and
  every third-party `uses:` pinned by SHA.
- A `permissions:` block at workflow level, set to the minimum the jobs need.
  A reusable workflow cannot grant itself more than the caller's token already has, so
  declaring it narrowly here documents the contract and fails loudly when a caller has
  not granted enough.
- A caller test, `.github/workflows/_test-<name>.yml`, triggered on `pull_request`
  with a `paths:` filter for the workflow file. Call the workflow by its local path so
  the test exercises the branch's version, not a released tag:

  ```yaml
  jobs:
    call:
      uses: ./.github/workflows/<name>.yml
      with:
        some-input: value
  ```

  Test what would actually break a consumer — that declared `outputs` really surface
  to the caller, and that an omitted optional input falls back to its default.
- A row in the workflow index in [`README.md`](README.md), documenting the inputs and
  any secret the caller has to pass.

Title the PR `feat: add <name> workflow` — a new workflow is a feature, and a minor
bump is what moves the `v1` tag to include it.

## Branch names

release-please ignores branch names entirely — it only reads commit subjects and
PR titles on `main` (its own release branch, `release-please--branches--main`, is
the exception, and it manages that one itself). Branch names are therefore a
human convention only. Mirror the commit type for readability:

```
<type>/<short-kebab-description>

feat/node-ci
fix/node-ci-cache-key
deps/bump-checkout
docs/pinning-policy
```
