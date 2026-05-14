# `release` configuration

> Schema source: [`brik.schema.json#$defs/release`](../../../schemas/config/v1/brik.schema.json)

The `release` stage computes the application version from Git tags and,
when the pipeline runs on a tag, optionally generates a changelog and
records the release. The whole section is optional; defaults match a
SemVer + Conventional Commits + `CHANGELOG.md` workflow.

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `release.strategy` | enum (`semver`, `calver`, `custom`) | `semver` | Release strategy. |
| `release.tag_prefix` | string | `v` | Prefix for release tags (e.g. 'v'). |

### `release.trigger`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `release.trigger.on-tag` | boolean | `true` | Run when the current commit carries a git tag. |
| `release.trigger.on-main` | boolean | `false` | Run on push to the default branch. |
| `release.trigger.manual` | boolean | `false` | Run only when the pipeline was triggered manually (BRIK_TRIGGER_MANUAL=true). |

### `release.changelog`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `release.changelog.enabled` | boolean | `true` | Whether to generate a changelog on release. |
| `release.changelog.format` | enum (`conventional`, `keep-a-changelog`) | `conventional` | Changelog format. |
| `release.changelog.file` | string | `CHANGELOG.md` | Path to the changelog file. |

<!-- END AUTO-GENERATED -->

`release.changelog.file` is interpreted relative to `BRIK_WORKSPACE`
when the path is not absolute.

## Behaviour

- **Always**: the release stage computes the current version from the
  most recent Git tag matching `<tag_prefix>X.Y.Z` and exports it as
  `BRIK_APP_VERSION`. Subsequent stages (build, package, publish) read
  that variable.
- **On a tag push**: in addition, the stage prepares the release. With
  `changelog.enabled: true` the changelog is generated, prepended to
  `release.changelog.file`, committed, and the tag is finalised.
- **Off a tag push**: only the version computation runs. No changelog,
  no commit, no tag.

## Strategy semantics

| Strategy | Status | Effect |
|----------|--------|--------|
| `semver` | implemented | Version is the latest `<tag_prefix>X.Y.Z` tag (e.g. `v1.4.2`). |
| `calver` | accepted by schema, not yet wired | Treated as `semver` at runtime. |
| `custom` | accepted by schema, not yet wired | Treated as `semver` at runtime. |

`changelog.format: keep-a-changelog` is in the same situation: the
field is accepted by the schema and exported, but the changelog
generator currently emits the `conventional` format only.

## Examples

### Defaults (omit the section entirely)

```yaml
version: 1
project:
  name: my-app
```

Equivalent to: `strategy: semver`, `tag_prefix: v`, changelog enabled,
written to `CHANGELOG.md`, format `conventional`.

### Custom tag prefix

```yaml
version: 1
project:
  name: my-lib
release:
  tag_prefix: "release-"
```

Tags like `release-2.0.0` are recognised; tags like `v2.0.0` are
ignored.

### Disable changelog generation

```yaml
version: 1
project:
  name: nightly
release:
  changelog:
    enabled: false
```

The release stage still computes the version on every run and still
finalises the tag on a tag push, but no `CHANGELOG.md` is written or
committed.

### Relocate the changelog

```yaml
version: 1
project:
  name: my-app
release:
  changelog:
    file: docs/CHANGELOG.md
```

The path is interpreted relative to the workspace root.

## See also

- [`reference/git.md`](git.md) - identity used to commit the changelog and push the tag
- [`reference/build.md`](build.md) - how `BRIK_APP_VERSION` flows into build artifacts
- [`reference/package.md`](package.md) - tagging Docker images with the computed version
- [`overview.md`](../overview.md) - declarative model
