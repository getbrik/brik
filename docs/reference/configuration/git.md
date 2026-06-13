# `git`

> Pin the Git identity Brik uses when a stage commits or annotates a tag.

**Section:** `git` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/git`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Decide *who authors the commits and tags Brik creates on your behalf*.

CI runners are ephemeral and ship without a Git identity, so something has to
supply a `user.name` and `user.email` before any commit can be made. This
section lets you set that identity explicitly, typically a fixed bot identity,
instead of inheriting whoever happened to trigger the pipeline.

You rarely configure this section. When it is absent Brik falls back to the CI
platform's author variables, then to a built-in `Brik CI` default.

## What it does

- Applies the resolved identity via `git config --global` before any stage
  that commits or annotates a tag.

- Resolves each of `email` and `name` independently, taking the first
  non-empty value in order: `brik.yml`, then CI platform variables
  (`GITLAB_USER_EMAIL` / `CHANGE_AUTHOR_EMAIL` for the email,
  `GITLAB_USER_NAME` / `CHANGE_AUTHOR_DISPLAY_NAME` for the name), then the
  `brik-ci@brik.local` / `Brik CI` fallback.

- Exports the resolved values as `BRIK_GIT_USER_EMAIL` and
  `BRIK_GIT_USER_NAME` and writes them to the pipeline env file, so every later
  stage shares the same identity.

## When it runs

This section is cross-cutting. It does not drive a stage of its own.

The identity is used by the Release stage when it commits the generated
changelog and annotates the release tag. It is also used by the Deploy stage's
GitOps target when it commits the updated manifest to the config repository.

If the pipeline never commits or pushes, no release on a tag and no GitOps
deploy, the identity is never used and the section can be omitted.

## How to configure

The whole section is optional; set `git.user.*` only to pin a fixed identity.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `git.user`

Git user identity applied via 'git config --global' before stages that commit or annotate tags.

| Field | Type | Default |
|-------|------|---------|
| `git.user.email` | `string` | -- |
| `git.user.name` | `string` | -- |

- **`git.user.email`**

  Git user.email. If absent, falls back to CI-platform vars (GITLAB_USER_EMAIL, CHANGE_AUTHOR_EMAIL) then to brik-ci@brik.local.

- **`git.user.name`**

  Git user.name. If absent, falls back to CI-platform vars then to 'Brik CI'.


*Example*

```yaml
git:
  user:
    email: ci@example.com
    name: Brik CI
```

<!-- END AUTO-GENERATED -->

Set `git.user.*` explicitly only when you want every commit to carry a fixed
bot identity regardless of which user triggered the pipeline.

### Examples

Per-field examples are above. These are whole-section scenarios.

Pin a fixed bot identity. Every release commit and every GitOps deploy commit
is authored by `Brik CI <ci@example.com>` regardless of the triggering user:

```yaml
version: 1
project:
  name: my-app
git:
  user:
    name: Brik CI
    email: ci@example.com
```

Pin the email only. The name still resolves from the platform variables, or
falls back to `Brik CI`:

```yaml
version: 1
project:
  name: my-app
git:
  user:
    email: ci@example.com
```

## See also

- [`release`](release.md) - the changelog commit and tag use this identity
- [`deploy`](deploy.md) - the GitOps target commits to the config repo with this identity
- [Fixed flows](../../concepts/fixed-flows.md) - where the Release and Deploy stages sit in the flow
- [`brik.yml` reference](README.md) - all top-level sections
