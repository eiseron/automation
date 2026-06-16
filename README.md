# automation

Reusable Ruby automation toolkit shared across Eiseron CI and ops. A single
CLI (`eiseron`) exposes small, well-tested automations that pipelines and
operators reuse instead of re-implementing logic inline.

Installed via a pinned git ref (no package registry yet):

```ruby
# Gemfile
gem "eiseron_automation", git: "https://gitlab.com/eiseron/stack/automation.git", tag: "v0.1.0"
```

## Commands

### `eiseron release tag`

Version-driven release tagging. Reads a bare semver from a version file and
creates the matching `v<version>` git tag through the GitLab API, lifting and
restoring tag protection around the create. Repos protect tags at "no one"
(Terraform-managed in `eiseron-ops`), so this command — running on a protected
ref with the protected `EISERON_STACK_TOKEN` — is the only way a tag gets
created. A tag therefore always maps to a reviewed change that bumped the
version file.

Environment (all provided by GitLab CI on a protected ref):

| variable | purpose |
|----------|---------|
| `EISERON_STACK_TOKEN` | Maintainer-role token used for the tag + protection API calls |
| `CI_API_V4_URL`, `CI_PROJECT_ID`, `CI_COMMIT_SHA` | target project + commit |
| `VERSION_FILE` | path to the bare-semver file (default `VERSION`) |

Behaviour:

- rejects an empty file, a `v`-prefixed value, and anything that is not
  `MAJOR.MINOR.PATCH` (optionally with a `-prerelease`/`+build` suffix), each
  with a specific message;
- idempotent — skips if the tag already exists;
- restores `create_access_level: no one` even if the tag create fails.

Used by `stack/ci`'s `release.yml` template, which installs this gem and runs
the command in consumers' `release` stage.

### `eiseron preview deploy` / `stop` / `sweep`

Per-merge-request preview environments on the shared host. These run from the
product's **ops repo** (protected scope, where the host credentials live) and
invoke the `eiseron.provisioning.preview_app` Ansible playbook over SSH, keeping
the complex orchestration in tested Ruby instead of inline CI shell.

- `deploy` brings MR `$PREVIEW_MR_IID` up: assembles `DATABASE_URL` from the
  tenant credentials (URL-encoding the password) merged with
  `PREVIEW_APP_EXTRA_ENV`, then runs the playbook with `state=present`.
- `stop` tears MR `$PREVIEW_MR_IID` down (`state=absent`).
- `sweep` reconciles: lists deployed previews (`docker ps`) against the scan
  project's still-open MRs (GitLab API) and tears down every preview whose MR
  is no longer open.

Consumed by `stack/ci`'s `preview-deploy.yml` and `preview-sweep.yml` templates.

Environment:

| variable | used by | purpose |
|----------|---------|---------|
| `EISERON_PREVIEW_APP` | all | product slug |
| `EISERON_PREVIEW_SUFFIX` | all | host/name suffix (e.g. `-preview`) |
| `EISERON_PREVIEW_ZONE` | deploy | preview DNS zone |
| `EISERON_PREVIEW_PORT` | deploy | app container port (default `4000`) |
| `EISERON_PREVIEW_DB_SCHEME` / `_DB_HOST` / `_DB_PORT` | deploy | `DATABASE_URL` parts |
| `EISERON_PREVIEW_SCAN_PROJECT` | sweep | project whose open MRs are kept |
| `PREVIEW_HOST_IP`, `ANSIBLE_PRIVATE_KEY_FILE` | all | host IP + SSH key path |
| `PREVIEW_MR_IID` | deploy/stop | the merge request number |
| `PREVIEW_APP_IMAGE`, `PREVIEW_APP_EXTRA_ENV` | deploy | image + extra env (JSON) |
| `PREVIEW_TENANT_NAME`, `PREVIEW_TENANT_PASSWORD` | all | tenant role credentials |
| `CI_API_V4_URL`, `PREVIEW_SWEEP_TOKEN` | sweep | GitLab API + read-api token |

### `eiseron go lint`

Lint gate for an Eiseron Go project. Runs `gofmt`, `go vet` and
`golangci-lint`, then enforces the org's no-comments rule: source carries no
line or block comments (rationale belongs in the MR description), the only
exception being `//go:` directives. Comment detection strips string, raw-string
and rune literals first, so a `//` inside a string is not a false positive, and
the restored module cache under `.cache/` is excluded from every scan. Raises
with the offending `file:line` on any violation.

Used by `stack/ci`'s `go.yml` template, which installs this gem and runs the
command in consumers' `lint` stage.

### `eiseron tofu lint`

No-comments gate for OpenTofu/Terraform source. Scans every `.tf` under the
working tree (excluding `.terraform/` and `.git/`) and raises with the
offending `file:line` if any carries a `#`, `//` or `/* */` comment. String
literals are stripped and heredoc bodies (`<<EOT`, `<<-EOT`, `<<"JSON"`) are
skipped before scanning, so URLs, hex colors and `#`/`//` inside embedded
scripts or policies are not false positives. Rationale belongs in the MR
description.

Used by `stack/ci`'s `tofu-lint.yml` template.

### `eiseron prod upload` / `trigger` / `deploy`

Production build/deploy steps, driven from `stack/ci`'s `prod-build.yml`
(product, on a tag) and `prod-deploy.yml` (the `-ops` repo, on the trigger).
Each skips gracefully (dormant) when its config vars are unset.

- `prod upload` — syncs the digested static tree to R2 via the aws-sdk-s3
  `TransferManager`; sets `Content-Type` per extension from `mime-types`;
  uploads assets (excludes `*.map`, `*.gz` — Cloudflare compresses at the edge)
  and sourcemaps (`*.map` only) to separate buckets. Reads `PROD_ASSETS_DIR`
  (default `priv/static`), `PROD_ASSETS_BUCKET`, `PROD_SOURCEMAPS_BUCKET`,
  `CLOUDFLARE_ACCOUNT_ID`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`.
- `prod trigger` — fires the `-ops` deploy pipeline (pipeline trigger token).
  Reads `PROD_DEPLOYER_PROJECT`, `PROD_DEPLOYER_TRIGGER_TOKEN`, `CI_COMMIT_TAG`,
  `CI_REGISTRY_IMAGE`, `CI_PROJECT_PATH`, `CI_API_V4_URL`.
- `prod tenant` — provisions the per-product Postgres role and database on the
  shared platform host over SSH (idempotent `CREATE ROLE`/`CREATE DATABASE`),
  seeding the role with the managed `PROD_TENANT_PASSWORD`. Reads
  `PROD_TENANT_SLUG`, `PROD_TENANT_PASSWORD`, `PROD_HOST`; `PG_CONTAINER`
  (default `platform-db`), `PG_ADMIN_USER` (default `eiseron`), `DEPLOY_SSH_USER`
  (default `deploy`).
- `prod deploy` — `kamal deploy` of the pre-built image with an anti-downgrade
  guard. Before deploying, idempotently re-applies `PROD_TENANT_PASSWORD` to the
  role (`ALTER ROLE`), so a normal deploy is a no-op and a rotated secret lands
  on the role; injects the assembled `DATABASE_URL` into the `kamal` subprocess
  only (never the CI environment). Reads `PROD_TAG`, `PROD_PROJECT`,
  `PROD_DEPLOY_READ_TOKEN`, `CI_API_V4_URL`, `PROD_TENANT_SLUG`,
  `PROD_TENANT_PASSWORD`, `PROD_HOST`, `DB_URL_SCHEME` (default `ecto`);
  `PROD_DEPLOY_ALLOW_OLD=true` (web pipeline only) lifts the guard.
- `prod setup` — first `kamal setup` of a host (boots the app); skips the
  anti-downgrade guard, re-applies the tenant password like `prod deploy`, and
  must run from a manual web pipeline.

Runtime gems: `mime-types` is a gem dependency (installed with the gem).
`prod upload` additionally needs `aws-sdk-s3` (lazily required to keep the other
commands light; the `stack/ci` job `gem install`s it), and `prod deploy` needs
`kamal` (provided by the `ops` image). A consumer running these outside the
`stack/ci` jobs must install those itself.

### `eiseron ci init` / `install` / `update` / `check`

Manages `stack/ci`'s dependency lockfile the way a package manager manages a
`Gemfile` + `Gemfile.lock`. `manifest.yml` declares
each dependency (`gems`, `repos`, `images`) keyed by its full source — a git path
or a Docker reference — with a version constraint (`~>`, `>=`, `=`, `*`); the
command picks the highest published version satisfying each constraint and pins it
to an immutable hash — git tags resolve to commit SHAs, images to registry
digests — writing a `variables:` block (`lock.yml`) the templates consume as
`$STACK_*` (kept off the GitLab-reserved `CI_*` namespace). Each pin carries its
full reference: gems/repos emit `STACK_<NAME>_REPO` plus `_REF`/`_SHA`, images
emit `STACK_<NAME>_IMAGE` (`registry/repo@digest`) plus `_TAG`, so the templates
never hardcode a URL or registry path.

- `ci init` — scaffolds an empty `manifest.yml` (`gems`/`repos`/`images`) if absent.
- `ci install` — resolves the manifest into `lock.yml`: creates it if absent,
  otherwise keeps every pin that still satisfies the manifest and re-resolves only
  the rest.
- `ci update [name…]` — re-resolves the named dependencies (all, if none given) to
  the highest version in range.
- `ci check` — frozen-lockfile verification for CI: fails when the lock is absent,
  missing a variable, or pinned to a version that no longer satisfies the manifest,
  and asserts the `gem-runtime` image's baked `automation_ref` label matches the
  locked automation SHA — the divergence that broke `db restore`.

Reads `STACK_MANIFEST` (default `manifest.yml`) and `STACK_LOCK` (default
`lock.yml`). Shells out to `git ls-remote` and `crane` (provided by the
`stack/ci` `lock-check` job); both are lazily invoked, so loading the gem needs
neither.

## Development

```sh
bundle install
bundle exec rake test     # minitest
bundle exec rubocop       # lint
```

Lint includes a custom cop, `Eiseron/NoComments` (`rubocop/eiseron/no_comments.rb`),
which forbids source comments so rationale stays in merge requests; magic
comments, shebangs, and `rubocop:` directives are allowed.

## Releasing

Bump `VERSION` in a merge request. On merge to `main`, the `release-tag` job
runs this repo's own CLI to tag `v<version>` (self-hosted release flow).
Maintenance releases: branch `release/X.Y`, bump `VERSION`, MR into it.
