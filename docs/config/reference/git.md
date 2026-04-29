# `git` configuration

> Schema source: [`brik.schema.json#$defs/git`](../../../schemas/config/v1/brik.schema.json)

The `git` section pins the Git identity that Brik applies via
`git config --global` before any stage that commits or annotates tags.
Concretely: the release stage's changelog commit and tag, and the
GitOps deploy stage's commit to the config repository.

CI runners are ephemeral and ship without a Git identity, which is why
this resolution exists at all.

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `git.user`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `git.user.email` | string | -- | Git user.email. If absent, falls back to CI-platform vars (GITLAB_USER_EMAIL, CHANGE_AUTHOR_EMAIL) then to brik-ci@brik.local. |
| `git.user.name` | string | -- | Git user.name. If absent, falls back to CI-platform vars then to 'Brik CI'. |

<!-- END AUTO-GENERATED -->

When the fields above are unset, Brik falls back to the CI platform
variables and finally to the `brik-ci@brik.local` / `Brik CI` defaults.
See *Resolution order* below.

## Resolution order

For each of `email` and `name`, the first non-empty value wins:

1. `brik.yml` -- `git.user.email` / `git.user.name`.
2. CI platform variables -- `GITLAB_USER_EMAIL` or `CHANGE_AUTHOR_EMAIL`
   for the email; `GITLAB_USER_NAME` or `CHANGE_AUTHOR_DISPLAY_NAME` for
   the name.
3. Fallback -- `brik-ci@brik.local` / `Brik CI`.

The resolved values are exported as `BRIK_GIT_USER_EMAIL` and
`BRIK_GIT_USER_NAME` and written to the pipeline env file, so all
later stages share the same identity.

## When the section can be omitted

- The pipeline never commits or pushes (no release on tag, no GitOps
  deploy). The fallback is then unused.
- The CI platform already exposes the human author via
  `GITLAB_USER_EMAIL` / `CHANGE_AUTHOR_EMAIL` and that is the desired
  attribution.

Set `git.user.*` explicitly only when you want every commit to carry a
fixed bot identity regardless of which user triggered the pipeline.

## Examples

### Defaults (no section)

```yaml
version: 1
project:
  name: my-app
```

The release stage will commit as the platform-detected user, falling
back to `Brik CI <brik-ci@brik.local>` if no platform variable is set.

### Pinned bot identity

```yaml
version: 1
project:
  name: my-app
git:
  user:
    name: Brik CI
    email: ci@example.com
```

Every release commit and every GitOps deploy commit will be authored
by `Brik CI <ci@example.com>` regardless of the triggering user.

### Email only

```yaml
version: 1
project:
  name: my-app
git:
  user:
    email: ci@example.com
```

Email is pinned; the name still resolves from the platform variables
(or falls back to `Brik CI`).

## See also

- [`reference/release.md`](release.md) - the changelog commit and tag use this identity
- [`reference/deploy.md`](deploy.md) - the GitOps target commits to the config repo with this identity
- [`overview.md`](../overview.md) - declarative model
