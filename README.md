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

## Development

```sh
bundle install
bundle exec rake test     # minitest
bundle exec rubocop       # lint
```

## Releasing

Bump `VERSION` in a merge request. On merge to `main`, the `release-tag` job
runs this repo's own CLI to tag `v<version>` (self-hosted release flow).
Maintenance releases: branch `release/X.Y`, bump `VERSION`, MR into it.
