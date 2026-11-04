# docker-hub-publish

Reference for
[`.github/workflows/docker-hub-publish.yml`](../.github/workflows/docker-hub-publish.yml):
the jobs it runs, the credential path it takes to Docker Hub, the gates it applies, and
the AWS objects a caller has to create for it.

Placeholders throughout: `<owner>` and `<repository>` are the **calling** repository,
`<directory>` one of the directories it hands over, `<namespace>` the Docker Hub account,
`<account-id>` the 12-digit AWS account id, `<region>` the AWS region and `<project>` a
name of the caller's choosing for its SSM paths.

## The four jobs

```
caller  ->  meta  ->  build (matrix: one leg per image directory)  -\
                                                                     >-  push
            compose  ------------------------------------------------/
            \______________ docker-hub-publish.yml _________________/
```

The caller holds the triggers, the concurrency group and every value belonging to its own
repository: the image directories, `aws-region`, `aws-ssm-parameter`,
`dockerhub-namespace` and the `aws-role-arn` secret. This workflow reads no `vars` and
names no AWS object.

**`build` and `compose` check out repository code and get `contents: read` with no
`id-token: write`.** `push` holds the credentials and **checks nothing out**, so
everything executing in it is a SHA-pinned action or a `run` block in the workflow file.
That split is an invariant; a change breaking it is a security regression.

`build` hands `push` an OCI archive and the digest it built, through an artifact.
**`push` re-derives the digest after staging and fails if it moved.** Each artifact also
carries the repository its image publishes to, so no step in `push` names a directory.
Before copying, `push` compares the two sets, catching a build that uploaded nothing or an
artifact that arrived twice.

`compose` loops over the compose directories rather than matrixing them, rendering only
and building nothing. Per directory it stages the whole directory, the `.env` included,
then renders it under `--profile '*'`. **The render proves the file loads, never that the
repository declares its own variables.** `config --variables` lists every name the file
interpolates without resolving any, and each gets a placeholder in a second env file
staged beside the first; `--env-file` turns the auto-loading of `.env` off, so both are
named explicitly and the directory's own file goes second, where the later file wins. A
bind source is the deployment's to name, and **the published artifact is the source file
byte for byte** — one layer, `application/vnd.docker.compose.file+yaml`, every `${...}`
intact — so no placeholder reaches what is published. One artifact carries every
directory, plus the manifest of directory names `push` reads. The job also asserts
`docker compose publish` exists on the runner. It carries no `if:` and so never skips,
which is what lets `push` keep a plain `needs` gate when no compose directory is given.

`push` carries `if: github.event_name == 'release'`. On every other event it skips, so a
pull request builds, scans and gates everything and publishes nothing.

**Renaming this file or this repository breaks every caller's AWS trust policy**, which
pins `job_workflow_ref` to its path. GitHub publishes no redirects for reusable workflows.

## What a caller must provide

| Requirement | Why |
| --- | --- |
| `id-token: write` on the calling job | `push` mints the OIDC token with it. A caller granting less fails at that job, not at parse time |
| A `.trivyignore.yaml` at the repository root | **Required even when it suppresses nothing.** See [The vulnerability gate](#the-vulnerability-gate) |
| A `Dockerfile` and a `docker-bake.hcl` declaring `target "image"` in each image directory | `bake-target: image` and `targets: image` are fixed in this workflow |
| A `compose.yaml` declaring `name: <repository>-<directory>` in each compose directory | Checked by `compose`. See [What the compose job gates](#what-the-compose-job-gates) |
| Non-nested directories | `compose` refuses a nested directory, and the build artifact is named `image-<directory>`, which cannot contain a slash |
| The AWS objects below | |

## How the credential is reached

Docker Hub supports no OIDC for personal accounts, so AWS stands in: the job mints a
GitHub OIDC token, exchanges it for temporary credentials on a role whose trust policy
accepts only one caller running this workflow at a version tag, and reads a Docker Hub PAT
out of SSM Parameter Store.

- The **role ARN is a secret at both ends**, because the runner echoes a step's `with:`
  block before the action runs. `mask-aws-account-id: true` masks the account id and the
  `authenticated-arn` STS returns, so a wrong ARN logs as `***`.
- **`role-session-name` carries the run id and attempt**, OIDC auth dropping the action's
  own session tags, so it is the only channel by which a run reaches CloudTrail.
- `aws-actions/configure-aws-credentials` runs `output-credentials: true` and
  **`output-env-credentials: false`**, so credentials are step outputs rather than job
  environment variables.
- The PAT is piped **straight** from `aws ssm get-parameter` into
  `docker login --password-stdin`, never occupying a variable, step output or file.
  `regctl` and `cosign` both read what `docker login` wrote.
- **`cosign-installer` runs before `regctl-installer`.** The regctl installer verifies its
  download against regclient's cosign signature `if [ -x "$(command -v cosign)" ]`.
- **`regctl` does the push**, copying the OCI layout's index byte for byte, so one digest
  spans the scan, the push, the attestations and the signature.

`push` dumps the decoded OIDC claims **before** its first AWS call, so a trust-policy
mismatch is diagnosable from the failed run itself. Only the payload is decoded; the token
is a live credential and never reaches the log.

Each image carries an SBOM and a SLSA provenance attestation at `mode=max`, which records
the **whole GitHub event payload**, on a pull request including its body. It is published,
so this is acceptable only while the **calling** repository is public. A private caller
should weigh `mode=min` before adopting this workflow.

Images are built for the runner's architecture. Publishing `linux/arm64` as well starts
with the caller's own build being able to produce it.

## The vulnerability gate

Each image is scanned by Trivy before anything is published, and a HIGH or CRITICAL
finding fails the release. The scan runs over the **unpacked** OCI layout: Trivy rejects
an archive outright, and a layout written by `regctl image import` leads with a referrers
index, which Trivy reads first, resolves nothing from, and then reports zero
vulnerabilities and success.

The gate therefore also asserts identity: **the `ImageID` Trivy reports has to name a
config present in the scanned layout and declaring a platform.** Pointed at a layout it
cannot walk, Trivy resolves the empty config `{}`, reports no findings and exits 0, and
`{}` declares no platform.

**Every caller needs a `.trivyignore.yaml` at its repository root, even an empty one.**
The scan step passes `trivyignores: .trivyignore.yaml` unconditionally, and Trivy treats a
named ignorefile that does not exist as a fatal error:

```
FATAL  Fatal error  flag error: unable to convert flags to options: ignore file not found: .trivyignore.yaml
```

That fails the scan before it looks at the image. A file whose whole content is
`vulnerabilities: []` satisfies it.

Give every suppression an `expired_at` date. On that date Trivy stops honouring the entry
and the finding fails the release again, so a suppression cannot outlive its reason by
being forgotten. Removing the date instead of extending it turns the file into a permanent
blind spot.

## What the compose job gates

The `compose` job fails a release whose `compose.yaml` does not declare
`name: <repository>-<directory>`, or whose directory is nested. The formula is the images'
own, so an operator reads the project, its network (`<repository>-<directory>_default`)
and its volumes off the artifact's reference, and two repositories cannot collide on one
host. The job reads the **declared** key rather than `config`'s resolved `.name`, which
`COMPOSE_PROJECT_NAME` would override — a deployer sets that to run a second copy beside
the first, and it does not change what is published.

It also fails a file whose unguarded names are not declared in the directory's own `.env`.
An unguarded `${VAR}` renders blank rather than failing, and `up` then reports
`invalid reference format` without naming it, so the declaration is the only guard left.
A `:-` default leaves the variable not required, so it must still be declared in `.env`;
a `:?` guard makes it required and needs no declaration.

This workflow sets **`IMAGE_PREFIX`**, to `<namespace>/<repository>`, and **`IMAGE_TAG`**,
to the tag being published, and names nothing else.

## The AWS objects

Created once, by hand. `<account-id>` never needs to appear in the calling repository: the
ARN carrying it is a repository **secret**. Everything here sits inside AWS's
**always-free** tier: IAM, STS, the OIDC provider, a standard-tier SSM parameter and the
AWS-managed `aws/ssm` key.

1. **Docker Hub.** Create each repository explicitly, so visibility is set before the
   first push. Then a personal access token with **Read & Write** and no Delete; a
   personal-account token's scope is the account.

2. **SSM parameter** `/<project>/release/dockerhub-pat`, SecureString, **standard tier**,
   encrypted with the default `alias/aws/ssm`. Standard tier is the free one, and it
   decrypts with the `kms:Decrypt` the policy below grants, where an advanced parameter
   uses `kms:GenerateDataKey`.

3. **IAM role** `gha-<repository>-release`, created as a Web identity role against the
   existing `token.actions.githubusercontent.com` provider with audience
   `sts.amazonaws.com` and nothing attached. Replace the trust policy the wizard generates
   wholesale:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "GitHubActionsReleaseTagsOnly",
         "Effect": "Allow",
         "Principal": {
           "Federated":
             "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub":
               "repo:<owner>@<owner-id>/<repository>@<repository-id>:ref:refs/tags/v*",
             "token.actions.githubusercontent.com:job_workflow_ref":
               "TomBorglum/workflows/.github/workflows/docker-hub-publish.yml@refs/tags/v*.*.*"
           }
         }
       }
     ]
   }
   ```

   **`sub` describes the caller and `job_workflow_ref` the called workflow, and the pair is
   the boundary.** `Principal.Federated` represents every repository on github.com, so the
   `Condition` block is the entire security boundary. Either claim alone is insufficient:
   `sub` on its own lets any workflow in the calling repository reach the role, and
   `job_workflow_ref` on its own lets **any repository at all** reach it by calling this
   public workflow.

   **`v*.*.*` on `job_workflow_ref` is deliberate.** A `StringLike` `*` matches dots, so
   two literal dots admit only the exact `vX.Y.Z` tags, which a ruleset in this repository
   makes immutable. The moving `vX` and `vX.Y` tags carry at most one dot and cannot
   match, so a caller cannot be re-pointed at new workflow content by someone moving a tag.
   **Pin the caller to an exact `vX.Y.Z`**, never `@v1`.

   The `sub` form above is the **immutable** one, carrying the owner and repository IDs.
   Repositories created after 15 July 2026 use it by default, and older ones can opt in
   under Settings → Actions → General. An older repository that has not opted in has
   `sub` of `repo:<owner>/<repository>:ref:refs/tags/v*` instead. Read the real value out
   of a claim dump rather than guessing which applies.

   **The key is `job_workflow_ref`.** AWS maps only the claims its condition-key reference
   lists, so a `StringLike` on a name outside that list leaves the one `Allow` statement
   unmatched and STS answers `Not authorized to perform sts:AssumeRoleWithWebIdentity`,
   naming no condition, with every other part correct. That is what `workflow_ref` as a key
   name looks like. GitHub's own reusable-workflow page says trust conditions on
   `job_workflow_ref` need a provider supporting custom claims and names only Google Cloud
   and HashiCorp Vault; **that is out of date for AWS, which maps the key.** Do not
   restructure a working policy on the strength of it.

   **IAM Access Analyzer warns** that the `*` in `sub` "can allow requests from more
   sources than you intended" and recommends naming a branch. The check fires on a
   wildcard's presence; this one sits after the owner, the repository, the `ref:` claim
   type, `refs/tags/` and the `v`, so all it admits is which version number. Save through
   it.

   Then one inline policy:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "ReadDockerHubPat",
         "Effect": "Allow",
         "Action": "ssm:GetParameter",
         "Resource":
           "arn:aws:ssm:<region>:<account-id>:parameter/<project>/release/dockerhub-pat"
       },
       {
         "Sid": "DecryptViaSsmOnly",
         "Effect": "Allow",
         "Action": "kms:Decrypt",
         "Resource": "arn:aws:kms:<region>:<account-id>:key/<aws/ssm key id>",
         "Condition": {
           "StringEquals": { "kms:ViaService": "ssm.<region>.amazonaws.com" }
         }
       }
     ]
   }
   ```

   **With a shared key the isolation boundary is that parameter ARN alone.** `aws/ssm`
   grants `kms:Decrypt` to any caller in the account authorised for SSM, so the literal
   parameter path above, rather than a prefix, is what holds this role away from every
   other parameter under the same key.

4. **Repository variables and one secret** in the calling repository.

   - **Secret** holding `arn:aws:iam::<account-id>:role/gha-<repository>-release`, passed
     as the `aws-role-arn` secret. A fork's pull request gets no secrets, and `push` runs
     on the release event alone.
   - The Docker Hub namespace, passed as `dockerhub-namespace`. It has to be the account
     the PAT belongs to, which nothing checks.
   - The region, passed as `aws-region`.

   The SSM path is neither: the caller passes it as the `aws-ssm-parameter` input. It is
   not a secret — a path is an address, and the value it points at never leaves the step
   that reads it.

## Restricting who can create tags

Trust is pinned to this workflow at a version tag, and a workflow file is repository
content. Anyone able to create a matching tag in **either** repository can change what the
role trusts: a tag in the caller satisfies `sub`, and a tag in this repository carrying an
altered workflow satisfies `job_workflow_ref`.

Branch protection does not close this. A ruleset on the default branch gates what reaches
`main`; it says nothing about what a tag points at. Close it in both repositories with a
**tag** ruleset carrying **Restrict creations**, **Restrict deletions** and **Block force
pushes**, and only the release automation as a bypass actor.

Where tags are major-aliased — this repository force-moves `vX` and `vX.Y` after each
release — the ruleset has to cover `refs/tags/v*` rather than `refs/tags/v*.*.*`, and the
automation needs the bypass or its own tag step fails.

Verify rather than assume, for each repository:

```sh
gh api repos/<owner>/<repository>/rulesets --jq '.[] | {name, target}'
gh api repos/<owner>/<repository>/rulesets/<id> \
  --jq '{conditions, rules: [.rules[].type], bypass_actors}'
```

A tag ruleset whose rules are `deletion` and `non_fast_forward` alone makes existing tags
immutable and still lets anyone with write access create a new one.

## Verifying a release

```sh
docker buildx imagetools inspect <namespace>/<repository>-<directory>:<version>
cosign verify <namespace>/<repository>-<directory>@sha256:<digest> \
  --certificate-identity-regexp '.*<repository>.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
docker compose -f oci://docker.io/<namespace>/<repository>-<directory>:<version> config
```

`cosign-installer`'s default is cosign 3, which attaches the signature as an **OCI 1.1
referrer** rather than a `sha256-<digest>.sig` tag, so a tag listing shows the published
tags and nothing more.

**If the exchange is refused**, read the claim dump in the failed `push` job, correct the
trust policy in the console and re-run the failed job: the AWS side lives outside the tag,
so that loop is free.

**If the workflow file itself is wrong**, a `release` event runs the caller as it exists on
the tag, so the fix is a patch release of the caller — or, for a bug in this workflow, a
patch release here and a bumped pin.

**A release run must never be cancelled**, where a superseded pull request run should be.
Declare the concurrency group in the **caller**, because GitHub cancels the caller when
caller and called share a group, and condition `cancel-in-progress` on the event: a run
stopped partway through `push` can leave one image published and another not.
