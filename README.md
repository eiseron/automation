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

### `eiseron preview trigger` / `dispatch` / `deploy` / `stop` / `sweep`

Per-MR and per-main preview environments. The flow has two sides: the **app
repo** (where build_image runs) sends a downstream pipeline trigger to the
**ops repo**, which runs the deploy/stop/sweep against the shared preview VPS.
Consumer-facing templates live in `stack/ci` (`preview-app.yml` on the app
side, `preview-dispatch.yml` on the ops side).

- `trigger` (app side) — POSTs to `PREVIEW_DEPLOYER_PROJECT`'s pipeline
  trigger token with `PREVIEW_ACTION` and the per-MR / per-main payload.
  Used by `deploy_preview` / `deploy_main` / `stop_preview` in
  `preview-app.yml`. Trigger tokens bypass push-protection on the ops main
  branch, which native `trigger:project:` bridges cannot.
- `dispatch` (ops side) — reads `PREVIEW_ACTION` and routes to
  `deploy` / `stop` / `sweep`.
- `deploy` — full per-preview deploy on the host: writes docker auth,
  pulls the per-ref image, stops any previous compose project for the ref,
  ensures shared `<app>_app` / `<app>_admin` roles, recreates per-MR
  `<app>_<ref>_app` / `<app>_<ref>_admin` roles and the `<app>_<ref>`
  database with freshly-generated passwords (`SecureRandom`), runs the
  migrate one-shot as the admin role, renders the compose template + brings
  up the project, awaits the CF-Access-protected `/healthz` for 90s, then
  deletes the per-ref tags from the registry.
- `stop` — force teardown of a single MR ref regardless of state.
  Compose `down -v --rmi all --remove-orphans` + drop DB + roles + delete
  registry tag.
- `sweep` — reconciler: lists `mr-*` compose projects on the host, reads
  each container's `<app>.preview.mr_iid` label, queries the MR's state via
  the GitLab API, and tears down anything that is no longer `opened` (the
  `mr-` filter is the structural guarantee that the `main` project is
  immune to sweep mistakes).

Long refs are auto-compacted under Postgres' 63-byte identifier limit by
appending an 8-char SHA1 prefix; two long refs with the same leading bytes
get distinct DB/role names.

Consumed by `stack/ci`'s `preview-app.yml` (app side) and
`preview-dispatch.yml` (ops side).

Environment:

| variable | used by | purpose |
|----------|---------|---------|
| `PREVIEW_ACTION` | dispatch | one of `deploy` / `stop` / `sweep` |
| `PREVIEW_TRIGGER_ACTION` / `_KIND` / `_REF` / `_MR_IID` | trigger | payload to send downstream |
| `PREVIEW_DEPLOYER_PROJECT` / `_TRIGGER_TOKEN` / `_REF` | trigger | downstream ops project + trigger token |
| `PREVIEW_REF` / `_SHA` / `_KIND` / `_MR_IID` | dispatch/deploy/stop/sweep | identifies the deploy target |
| `PREVIEW_IMAGE_REPO` | deploy | per-ref image lives at `<repo>:<ref>` |
| `PREVIEW_IMAGE_PULL_USER` / `_TOKEN` | deploy | deploy token for `docker pull` on the host |
| `PREVIEW_DOMAIN_BASE` | deploy | URL is `<ref>-<PREVIEW_DOMAIN_BASE><health_path>` |
| `PREVIEW_SECRET_KEY_BASE` | deploy | Phoenix `SECRET_KEY_BASE` |
| `PREVIEW_HEALTHCHECK_TOKEN_ID` / `_SECRET` | deploy | CF Access service token (bypasses SSO on `/healthz`) |
| `PREVIEW_PROJECT_PATH` | registry | URL-encoded GitLab project path (e.g. `eiseron/afinados/afinados`) |
| `EISERON_PREVIEW_APP_NAME` | deploy/stop/sweep | product slug; drives role / DB names |
| `EISERON_PREVIEW_COMPOSE_TEMPLATE` | deploy | path to the compose template the consumer ships |
| `EISERON_PREVIEW_MIX_ENV` | deploy | `MIX_ENV` for migrate + runtime (default `preview`) |
| `EISERON_PREVIEW_HEALTH_PATH` | deploy | healthcheck path (default `/healthz`) |
| `EISERON_PREVIEW_DB_CONTAINER` / `_NETWORK` / `_URL_SCHEME` | deploy | shared Postgres location + DSN scheme |
| `EISERON_PREVIEW_MIGRATE_COMMAND` | deploy | one-shot migrate (default `mix ecto.migrate`) |
| `EISERON_PREVIEW_SERVICE` | sweep | service name inside compose for `ps -q` (default = app name) |
| `VPS_USER` / `PREVIEW_HOST_IP` / `ANSIBLE_SSH_PRIVATE_KEY` | deploy/stop/sweep | SSH onto the preview host |
| `SHARED_PG_USER` | deploy/stop | superuser of the shared `shared-pg` container (trust via socket) |
| `GITLAB_API_TOKEN`, `CI_API_V4_URL` | registry/sweep | GitLab API for MR state + tag delete |

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
  and asserts that **every** baked image with an `automation_ref` label matches the
  locked automation SHA — the divergence that broke `db restore`. Images that do
  not bake the gem (no `automation_ref` label) are silently skipped, so the check
  naturally extends to whichever images opt in by declaring the label.

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
