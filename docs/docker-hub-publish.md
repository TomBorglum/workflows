# docker-hub-publish

Reference for
[`.github/workflows/docker-hub-publish.yml`](../.github/workflows/docker-hub-publish.yml):
what a caller must provide, what fails a release, and the AWS and GitHub objects that live
outside the repository. The workflow file documents its own jobs and steps.

Placeholders throughout: `<owner>` and `<repository>` are the **calling** repository,
`<directory>` one of the directories it hands over, `<namespace>` the Docker Hub account,
`<account-id>` the 12-digit AWS account id, `<region>` the AWS region and `<project>` a
name of the caller's choosing for its SSM paths.

**Renaming this file or this repository breaks every caller's AWS trust policy**, which
pins `job_workflow_ref` to its path. GitHub publishes no redirects for reusable workflows.

The OIDC exchange is performed by
[`TomBorglum/actions/aws/assume-role`](https://github.com/TomBorglum/actions/tree/main/aws/assume-role),
which the `push` job calls at a 40-char commit SHA. The `# vX.Y.Z` comment beside it is a
label; the SHA alone decides which version of the action's scripts runs beside the live
credential.

A composite action appears in no OIDC claim. `sub`, `job_workflow_ref` and
`job_workflow_sha` describe the calling repository and this workflow file, so the trust
policy below is unaffected by it.

## What a caller must provide

| Requirement | Why |
| --- | --- |
| `id-token: write` on the calling job | The permissions ceiling is validated at run start, so a caller granting less fails with `startup_failure` and no job logs |
| The triggers and the concurrency group | This workflow declares neither. See [Concurrency](#concurrency) |
| A config file declaring what the repository publishes, `.github/docker-hub-publish.yml` by default | The one place image directories, compose projects, suppressions and the gate are declared. `README.md` documents every key |
| A `Dockerfile` and a `docker-bake.hcl` declaring `target "image"` per image directory | `bake-target: image` and `targets: image` are fixed in this workflow |
| A `compose.yaml` declaring `name: <repository>-<directory>` per compose directory | Gated. See [What fails a release](#what-fails-a-release) |
| Non-nested directories | `compose` refuses a nested directory, and the build artifact is named `image-<directory>`, which cannot contain a slash |
| A Docker Hub namespace matching the PAT's own account | Nothing checks it |
| The AWS objects below | |

No `.env` file is required beside a compose file, and no `.trivyignore` file is required
anywhere: an image with nothing to suppress is one key in the config file and no more.

`push` runs on the `release` event alone. Every other event builds, scans and gates, and
publishes nothing.

Images are built for the runner's architecture. Publishing `linux/arm64` as well starts
with the caller's own build being able to produce it.

## The image metadata contract

`docker/metadata-action` derives the tags, labels and annotations **once** for every
image. `docker/bake-action` then builds each directory with the derived values layered
**under** the directory's own `docker-bake.hcl`, which is passed last and so wins every
key it names.

What the caller's bake file owns:

- **`target "image"`, carrying no `tags`.** The build exports an OCI archive and the
  publishing job names the images from the derived tags.
- **`labels`**, a map that merges per key: a key declared here replaces the derived value,
  and every key it does not name survives.
- **`annotations`**, a list that is appended to rather than replaced.
- **`context` and `dockerfile`.** The directory is passed as bake's `source`, so both
  resolve the way a plain `docker build` resolves them: `context` against the directory,
  `dockerfile` against the context. A `context` above the directory builds and needs
  nothing from the caller.

The derived metadata is the `org.opencontainers.image.*` set, carried as both labels and
manifest annotations. **`title` and `description` are the two worth declaring per image**,
because the derived values describe the repository and are therefore identical for every
image in it.

Four tags are published per image, and per compose artifact, derived from the release tag:

| Tag | Example |
| --- | --- |
| `{{version}}` | `1.2.3` |
| `{{major}}.{{minor}}` | `1.2` |
| `sha-<full commit>` | `sha-a1b2c3d4...` |
| `latest` | `latest` |

`latest=false` is set on the derivation, so `latest` is declared like any other pattern
rather than implied by a semver tag, and it is applied on the `release` event alone.

## What fails a release

A **HIGH or CRITICAL** Trivy finding in any image.

Suppressions go in a **`trivyignores`** list under that image's own directory in the config
file: `.trivyignore` or `.trivyignore.yaml` files, one file per element, resolved against
the image directory.

```yaml
images:
  directories:
    frontend:
      trivyignores:
        - .trivyignore.yaml
```

**Per image.** A CVE shared by two images is fixed in one of them first: the day `frontend`
is rebuilt clean, its entry is deleted from `frontend/.trivyignore.yaml` and `backend` is
untouched. One shared file makes that impossible without splitting the file, and until it is
split the stale entry masks a regression in the image that was fixed. A path that is absolute
or contains a `..` component is refused, so the coupling cannot be expressed.

Give every suppression an `expired_at` date. On that date Trivy stops honouring the entry
and the finding fails the release again, so a suppression cannot outlive its reason by
being forgotten. Removing the date instead of extending it turns the file into a permanent
blind spot.

A finding that is unreachable in the image belongs in a **`vex-documents`** list instead,
beside `trivyignores` under the same image and resolved the same way: OpenVEX documents,
one file per element, applied to that image's scan alone. A `not_affected` or `fixed`
statement suppresses its finding; an `affected` or `under_investigation` one does not,
so recording a reachable finding there does not hide it from the gate. The split is by
what expires. Unreachability is a property of the image and does not rot, so a VEX
statement carries a justification and no date; a finding merely waiting for a fix keeps
a dated `.trivyignore` entry.

## Which events a HIGH or CRITICAL finding fails

The scan produces two independent checks. The **wrong-image check** proves trivy scanned
this image: pointed at a layout it cannot walk, trivy resolves the empty config `{}`,
reports nothing and exits 0, so a broken scan and a clean image look identical. The
**vulnerability check** is the HIGH or CRITICAL findings themselves.

**`images.gates.vulnerability`** in the config file moves the vulnerability check and
nothing else. `always`, the default, fails every caller event. `release` fails a release
and, on a `pull_request`, writes the findings to the job summary and passes.

```yaml
images:
  gates:
    vulnerability: release
```

It is nested under `images:` because it governs image scans and nothing else is scanned. A
second gate, should another scanner be added, is one more key here rather than one more
input.

`release` is for a repository that will not have a pull request blocked by drift in a base
image its author does not control: a base whose packages have a published fix the upstream
image has not been rebuilt with produces findings on every pull request, including ones that
change nothing near an image, and the contributor cannot act on any of them.

**The wrong-image check is never relaxed**, under either value. Relaxing it would let a
broken scan read as a clean image.

Both values print the findings to the step log. `release` adds the job summary table.

Not covered by this repository's caller test: the advisory branch needs an image carrying
HIGH or CRITICAL findings, and `_test-docker-hub-publish.yml` builds `fixture-image` from
`scratch` precisely so the required check cannot fail on a CVE published against a base.
A second call job is not the way round it either, because the `compose` job's artifact
name is the fixed literal `compose-files` and two calls in one run collide on it. The
branch is verified in the consuming repository.

A `compose.yaml` **not declaring `name: <repository>-<directory>`**. The formula is the
images' own, so an operator reads the project, its network
(`<repository>-<directory>_default`) and its volumes off the artifact's reference, and two
repositories cannot collide on one host. The **declared** key is what is read, not
`config`'s resolved `.name`, so setting `COMPOSE_PROJECT_NAME` does not satisfy this.

A `compose.yaml` carrying a name with **neither a `:?` guard nor a `:-` default**. The
compose file is published uninterpolated, so a deploy host resolves every name itself with
no env file of any kind. A `:?` fails naming the variable, and a `:-` default renders
deliberately and travels inside the artifact. A bare `${VAR}` renders an empty string and
says nothing; `up` then reports `invalid reference format` without naming it. `${VAR:-}` is
indistinguishable from bare and is refused with it.

This workflow sets **`IMAGE_PREFIX`**, to `<namespace>/<repository>`, and **`IMAGE_TAG`**,
to the tag being published, and names nothing else.

## What is published

Per image directory, `<namespace>/<repository>-<directory>` at the release tag, carrying an
SBOM and a SLSA provenance attestation, plus a cosign signature.

Per compose directory, `<namespace>/<repository>-<directory>` as an OCI compose artifact of
two layers: the source `compose.yaml` **byte for byte**, every `${...}` intact, and an
`image-digests.yaml` naming each service's image at its digest. `--with-env` is not passed,
so no env file is published and no value from one reaches the artifact.

Provenance runs at `mode=max`, which records the **whole GitHub event payload**, on a pull
request including its body. It is published, so this is acceptable only while the
**calling** repository is public. A private caller should weigh `mode=min` before adopting
this workflow.

## The AWS objects

Created once, by hand. `<account-id>` never needs to appear in the calling repository: the
ARN carrying it is a repository **secret**. Everything here sits inside AWS's
**always-free** tier: IAM, STS, the OIDC provider, a standard-tier SSM parameter and the
AWS-managed `aws/ssm` key.

Docker Hub supports no OIDC for personal accounts, which is why AWS stands in at all: the
job mints a GitHub OIDC token, exchanges it for temporary credentials on a role whose trust
policy accepts only one caller running this workflow at a version tag, and reads a Docker
Hub PAT out of SSM Parameter Store.

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
   two literal dots admit only the exact `vX.Y.Z` tags. The moving `vX` and `vX.Y` tags
   carry at most one dot and cannot match, so a caller cannot be re-pointed at new workflow
   content by someone moving a tag.

   That rests on an exact `vX.Y.Z` being immutable, which needs a **Restrict updates**
   rule and no bypass actor. `Restrict deletions` and `Block force pushes` do not give it:
   neither blocks `git tag -f` followed by a push to an existing tag ref, so any bypass
   actor can move one. See "Restricting who can create tags" below.
   **Pin the caller to an exact `vX.Y.Z`**, never `@v1`.

   The `sub` form above is the **immutable** one, carrying the owner and repository IDs.
   Repositories created after 15 July 2026 use it by default, and older ones can opt in
   under Settings → Actions → OIDC. An older repository that has not opted in has
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

   **IAM Access Analyzer raises two security warnings** on this policy. Both are
   advisory and Save stays enabled.

   The `*` in `sub` "can allow requests from more sources than you intended", with a
   recommendation to name a branch. The check fires on a wildcard's presence; this one
   sits after the owner, the repository, the `ref:` claim type, `refs/tags/` and the `v`,
   so all it admits is which version number.

   `Overly permissive use of wildcard for the
   token.actions.githubusercontent.com:job_workflow_ref condition key. Use the wildcard
   preceded by 6 consecutive characters.` The second and third `*` in `v*.*.*` are each
   preceded by one literal `.`. The check counts literal characters and does not model the
   claim: the two dots are the control, and loosening to `v1.*` would pass it while
   admitting the force-moved `v1.1`.

   Save through both.

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

4. **One secret and two values** in the calling repository.

   - **Secret** holding `arn:aws:iam::<account-id>:role/gha-<repository>-release`, passed
     as the `aws-role-arn` secret. The role ARN is a secret at both ends because the runner
     echoes a step's `with:` block before the action runs. A fork's pull request gets no
     secrets, and `push` runs on the release event alone.
   - The Docker Hub namespace, passed as `dockerhub-namespace`.
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
`main`; it says nothing about what a tag points at.

Close it in both repositories with **two** tag rulesets. Bypass actors are configured per
ruleset rather than per rule, so one ruleset cannot both let the release automation create
an exact version tag and stop it from moving one afterwards:

| Ruleset | Include | Rules | Bypass |
| --- | --- | --- | --- |
| `version-tags` | `refs/tags/v*` | Restrict creations, Restrict updates, Restrict deletions, Block force pushes | the release App, mode **Always** |
| `released-versions` | `refs/tags/v*.*.*` | Restrict updates, Restrict deletions, Block force pushes | **none** |

`version-tags` covers `refs/tags/v*` rather than `refs/tags/v*.*.*` because this repository
force-moves `vX` and `vX.Y` after each release, and the automation needs the bypass there
or its own tag step fails. `released-versions` omits **Restrict creations**, which is what
still lets the automation cut a release. Rulesets are additive, so its three rules apply to
an exact version on top of the first ruleset's and deny the App too.

A release tag created wrong can no longer be corrected in place. Repairing one means
disabling `released-versions`, fixing the tag and re-enabling it.

Verify rather than assume, for each repository:

```sh
gh api repos/<owner>/<repository>/rulesets --jq '.[] | {name, target}'
gh api repos/<owner>/<repository>/rulesets/<id> \
  --jq '{conditions, rules: [.rules[].type], bypass_actors}'
```

A tag ruleset whose rules are `deletion` and `non_fast_forward` alone makes neither
guarantee: anyone with write access can still create a new matching tag, and anyone who can
bypass the ruleset can still move an existing one. `creation` closes the first and `update`
the second, and only an empty bypass list closes the second against the automation.

## Concurrency

Declare the concurrency group in the **caller**. GitHub cancels the caller when caller and
called share a group, and a run stopped partway through `push` can leave one image
published and another not. Condition `cancel-in-progress` on the event: **a release run
must never be cancelled**, where a superseded pull request run should be.

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

**If the exchange is refused**, read the decoded OIDC claims the `push` job dumps before
its first AWS call, correct the trust policy in the console and re-run the failed job: the
AWS side lives outside the tag, so that loop is free.

**If the workflow file itself is wrong**, a `release` event runs the caller as it exists on
the tag, so the fix is a patch release of the caller — or, for a bug in this workflow, a
patch release here and a bumped pin.
