# `release`

> [!NOTE]
> Compute the application version from git tags. On a tag, also generate the
> changelog and finalise the release.

**Section:** `release` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/release`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Decide *what version this build is*, from your git tags.

Every downstream stage (build, package, publish, deploy) then refers to the
same version. A tagged commit can also cut a changelog and finalise the release.

You almost never configure this section. The defaults already follow a SemVer
and Conventional Commits workflow that writes to `CHANGELOG.md`.

## What it does

- **Always**: it computes the current version from the most recent
  `<tag_prefix>X.Y.Z` tag and exports it as `BRIK_APP_VERSION`. Build, package,
  and publish read that variable.

- **On a tag push**: it also prepares the release. With
  `changelog.enabled: true`, the changelog is generated, prepended to
  `release.changelog.file`, committed, and the tag is finalised.

Unimplemented options fall back to a working default. Each one is noted per
field under "How to configure" below.

## When it runs

By default the release runs on a **tag push**.

You can broaden that with `release.trigger`. For example, set `on-main: true`
to also run on every push to the default branch.

The version computation is what the rest of the flow depends on, so it happens
on every run. The changelog and the tag are finalised only on a tag push.

## How to configure

The whole section is optional. Each field's type and default is in the table;
its description follows below.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `release.strategy` | enum (`semver`, `calver`, `custom`) | `semver` |
| `release.profile` | enum (`trunk-based`, `git-flow`, `github-flow`, `none`) | `none` |
| `release.tag_prefix` | `string` | `v` |

- **`release.strategy`**

  Release strategy.

  - **`semver`** (default): semantic versioning (the only strategy implemented)
  - **`calver`**: calendar versioning; not yet implemented, falls back to `semver` for now
  - **`custom`**: user-defined scheme; not yet implemented, falls back to `semver` for now

- **`release.profile`**

  Git workflow profile that drives candidate detection. The profile is informational (the planner stamps it into plan.json so adapters can branch on it); the promote stage consumes it to decide whether to push to the candidate or release registry.

  - **`trunk-based`**: candidate on every push to the default branch
  - **`git-flow`**: candidate on `release/*` branches
  - **`github-flow`**: candidate on every PR-merged commit on `main`
  - **`none`** (default): no candidate detection; the release stage runs only on a tag push

- **`release.tag_prefix`**

  Prefix for release tags (e.g. 'v').


*Example*

```yaml
release:
  strategy: semver
  profile: trunk-based
  tag_prefix: v
```

### `release.trigger`

When the release stage should run. At least one of the flags must be true for the stage to execute. When the entire block is absent, the legacy always-run behaviour is preserved.

| Field | Type | Default |
|-------|------|---------|
| `release.trigger.on-tag` | `boolean` | `true` |
| `release.trigger.on-main` | `boolean` | `false` |
| `release.trigger.manual` | `boolean` | `false` |

- **`release.trigger.on-tag`**

  Run when the current commit carries a git tag.

- **`release.trigger.on-main`**

  Run on push to the default branch.

- **`release.trigger.manual`**

  Run only when the pipeline was triggered manually (BRIK_TRIGGER_MANUAL=true).


*Example*

```yaml
release:
  trigger:
    on-tag: true
    on-main: true
    manual: true
```

### `release.candidate`

Candidate-zone artifact configuration. The candidate zone receives every successful build; the promote stage moves an audited candidate to the release zone on a tag push.

#### `release.candidate.docker`

Candidate Docker registry.

| Field | Type | Default |
|-------|------|---------|
| `release.candidate.docker.registry` | `string` | -- |
| `release.candidate.docker.image` | `string` | -- |
| `release.candidate.docker.username_var` | `string` | -- |
| `release.candidate.docker.password_var` | `string` | -- |

- **`release.candidate.docker.registry`**

  Hostname (and optional port) of the candidate Docker registry, e.g. 'registry.candidate.example.com'.

- **`release.candidate.docker.image`**

  Image path within the candidate registry, e.g. 'myteam/api'.

- **`release.candidate.docker.username_var`**

  Name of the environment variable holding the username for the candidate Docker registry (the value is never stored in brik.yml). The promote stage logs in with it before pulling the candidate. Omit for an anonymous-pull candidate registry.

- **`release.candidate.docker.password_var`**

  Name of the environment variable holding the password/token for the candidate Docker registry. The promote stage logs in with it before pulling the candidate.


*Example*

```yaml
release:
  candidate:
    docker:
      registry: registry.candidate.example.com
      image: myteam/api
      username_var: BRIK_CANDIDATE_DOCKER_USER
      password_var: BRIK_CANDIDATE_DOCKER_PASSWORD
```

### `release.release`

Release-zone artifact configuration. The release zone holds promoted artifacts; the promote stage tags and pushes there once a candidate is approved.

#### `release.release.docker`

Release Docker registry.

| Field | Type | Default |
|-------|------|---------|
| `release.release.docker.registry` | `string` | -- |
| `release.release.docker.image` | `string` | -- |
| `release.release.docker.username_var` | `string` | -- |
| `release.release.docker.password_var` | `string` | -- |

- **`release.release.docker.registry`**

  Hostname (and optional port) of the release Docker registry, e.g. 'registry.release.example.com'.

- **`release.release.docker.image`**

  Image path within the release registry, e.g. 'myteam/api'.

- **`release.release.docker.username_var`**

  Name of the environment variable holding the username for the release Docker registry (the value is never stored in brik.yml). The promote stage logs in with it before pushing the promoted image. Omit if the release registry needs no auth.

- **`release.release.docker.password_var`**

  Name of the environment variable holding the password/token for the release Docker registry. The promote stage logs in with it before pushing the promoted image.


*Example*

```yaml
release:
  release:
    docker:
      registry: registry.release.example.com
      image: myteam/api
      username_var: BRIK_RELEASE_DOCKER_USER
      password_var: BRIK_RELEASE_DOCKER_PASSWORD
```

### `release.changelog`

Changelog generation configuration.

| Field | Type | Default |
|-------|------|---------|
| `release.changelog.enabled` | `boolean` | `true` |
| `release.changelog.format` | enum (`conventional`, `keep-a-changelog`) | `conventional` |
| `release.changelog.file` | `string` | `CHANGELOG.md` |

- **`release.changelog.enabled`**

  Whether to generate a changelog on release.

- **`release.changelog.format`**

  Changelog format.

  - **`conventional`** (default): Conventional Commits; the only format emitted for now
  - **`keep-a-changelog`**: Keep a Changelog; not yet implemented

- **`release.changelog.file`**

  Path to the changelog file.


*Example*

```yaml
release:
  changelog:
    enabled: true
    format: conventional
    file: docs/CHANGELOG.md
```

<!-- END AUTO-GENERATED -->

`release.changelog.file` is interpreted relative to `BRIK_WORKSPACE` when the
path is not absolute.

### Examples

Per-field examples are under each field above. These are whole-section
scenarios that those do not show.

Use the defaults. Omit the section entirely and you get `strategy: semver`,
`tag_prefix: v`, changelog enabled, written to `CHANGELOG.md`, in the
`conventional` format:

```yaml
version: 1
project:
  name: my-app
```

Use a custom tag prefix. Recognise tags like `release-2.0.0`, and ignore
`v2.0.0`:

```yaml
release:
  tag_prefix: "release-"
```

Disable changelog generation (still computes the version and finalises the tag):

```yaml
release:
  changelog:
    enabled: false
```

## See also

- [`git`](git.md) - identity used to commit the changelog and push the tag
- [`build`](build.md) - how `BRIK_APP_VERSION` flows into build artifacts
- [`package`](package.md) - tagging Docker images with the computed version
- [Fixed flows](../../concepts/fixed-flows.md) - where the Release stage sits in the flow
- [`brik.yml` reference](README.md) - all top-level sections
