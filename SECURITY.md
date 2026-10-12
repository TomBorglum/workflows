# Security Policy

## Supported Versions

This repository publishes reusable GitHub Actions workflows. Fixes land only on `main`
and reach consumers through the next release; please reproduce against the latest
commit on `main` before reporting an issue.

Because the moving `vX` and `vX.Y` tags are repointed on every release, a consumer
pinned to `@v1` picks up a fix automatically. An exact `vX.Y.Z` tag or a commit SHA
is immutable by design and is **not** backpatched — a fix ships in the next release,
and pinning that precisely means taking on the job of bumping it.

## Reporting a Vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report privately via GitHub's
[private vulnerability reporting](https://github.com/TomBorglum/workflows/security/advisories/new)
(the **Security → Report a vulnerability** button on the repository). This keeps the
report confidential until a fix is available.

When reporting, please include:

- A description of the vulnerability and its impact.
- Steps to reproduce, or a proof of concept.
- The affected workflow(s) and the commit or tag you observed it on.

You can expect an acknowledgement within a few days. Once confirmed, a fix will be
prepared and a GitHub Security Advisory published crediting the reporter (unless you
prefer to remain anonymous).

## Scope & Notes

A reusable workflow runs **as a job in someone else's repository**, under their
`GITHUB_TOKEN` and with whatever secrets they pass it. The blast radius is wider than
a composite action's, because a whole job is being handed over rather than a step.
Four things follow, and all are in scope:

- **Secrets the caller hands over.** Callers commonly write `secrets: inherit`, which
  passes *every* secret in their repository, not a chosen few. Workflows here declare
  each secret they need explicitly in `on.workflow_call.secrets` so an `inherit`
  caller is not the only supported shape — and so a workflow that starts needing a new
  secret is a visible, breaking change rather than a silent new capability. A workflow
  reading a secret it never declared, or passing secrets on to a nested workflow
  beyond what it declared, is a vulnerability.
- **What a workflow executes.** Every third-party action referenced from a workflow
  here is pinned to a full commit SHA, not a tag, so an upstream tag being repointed
  cannot change what consumers run. Dependabot bumps those pins on a cooldown (see
  [`.github/dependabot.yml`](.github/dependabot.yml)) so a withdrawn or compromised
  upstream release has a window to surface before it is republished here.
- **What a workflow does with inputs.** Script injection through an unquoted `${{ }}`
  interpolation in a `run:` block, a secret written to the log or to `$GITHUB_OUTPUT`,
  or an input that escapes into a shell command are all in scope. Inputs from a caller
  are untrusted: a caller may be triggered by `pull_request_target` or `issue_comment`
  and be passing attacker-controlled text straight through.
- **Permissions.** Workflows here declare a minimal `permissions:` block. A workflow
  that quietly relies on a broader token than it declares, or that uses a caller's
  write permission for something outside its stated job, is in scope.

The moving `vX` / `vX.Y` tags are mutable **on purpose** — that is the published
contract, not a vulnerability. A report that these tags can change is not in scope;
consumers who need immutability pin a SHA.

Likewise, that this repository is **public** is a requirement, not an oversight:
GitHub only allows a public caller to call a reusable workflow in a public
repository.
