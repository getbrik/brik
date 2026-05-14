# `hooks` configuration

> Schema source: [`brik.schema.json#$defs/hooks`](../../../schemas/config/v1/brik.schema.json)

The `hooks` section attaches inline shell commands before or after each
pipeline stage. Hooks declared in `brik.yml` run alongside file-based
hooks at `.brik/hooks/<hook>.sh`; the two mechanisms coexist and both
fire.

`pre_*` hooks run before the stage and can abort it (non-zero exit).
`post_*` hooks run after the stage completes successfully and are
best-effort -- they cannot override the stage's exit code.

## Quick reference

Each hook value is a single inline shell command. Chain multiple
commands with `&&` or `;`. Empty strings are rejected by the schema.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hooks.pre_init` | string | -- | Commands executed before the init stage. |
| `hooks.post_init` | string | -- | Commands executed after the init stage completes successfully. |
| `hooks.pre_release` | string | -- | Commands executed before the release stage. |
| `hooks.post_release` | string | -- | Commands executed after the release stage completes successfully. |
| `hooks.pre_build` | string | -- | Commands executed before the build stage. |
| `hooks.post_build` | string | -- | Commands executed after the build stage completes successfully. |
| `hooks.pre_lint` | string | -- | Commands executed before the lint stage. |
| `hooks.post_lint` | string | -- | Commands executed after the lint stage completes successfully. |
| `hooks.pre_sast` | string | -- | Commands executed before the SAST scan. |
| `hooks.post_sast` | string | -- | Commands executed after the SAST scan completes successfully. |
| `hooks.pre_scan` | string | -- | Commands executed before the security scan stage. |
| `hooks.post_scan` | string | -- | Commands executed after the security scan stage completes successfully. |
| `hooks.pre_container_scan` | string | -- | Commands executed before the container scan. |
| `hooks.post_container_scan` | string | -- | Commands executed after the container scan completes successfully. |
| `hooks.pre_test` | string | -- | Commands executed before the test stage. |
| `hooks.post_test` | string | -- | Commands executed after the test stage completes successfully. |
| `hooks.pre_package` | string | -- | Commands executed before the package stage. |
| `hooks.post_package` | string | -- | Commands executed after the package stage completes successfully. |
| `hooks.pre_deploy` | string | -- | Commands executed before the deploy stage. |
| `hooks.post_deploy` | string | -- | Commands executed after the deploy stage completes successfully. |
| `hooks.pre_notify` | string | -- | Commands executed before the notify stage. |
| `hooks.post_notify` | string | -- | Commands executed after the notify stage completes successfully. |

<!-- END AUTO-GENERATED -->

## Behaviour

- The command is `eval`-ed in the runner's shell, with all
  Brik-exported variables (`BRIK_APP_VERSION`, `BRIK_PROJECT_NAME`,
  `BRIK_WORKSPACE`, ...) in scope.
- `brik.yml` is treated as trusted project config (same trust level as
  the project's own code) -- there is no sandbox.
- File-based hooks (`.brik/hooks/pre_<stage>.sh`) are sourced and run in
  addition to the inline command, after it. Failure of either path
  aborts the stage in the `pre_*` case.
- A hook value must be non-empty (`minLength: 1`).

## Examples

### Single inline command

```yaml
version: 1
project:
  name: my-app
hooks:
  pre_build: ./scripts/clean.sh
```

### Chained commands with `&&`

```yaml
version: 1
project:
  name: my-app
hooks:
  pre_build: ./scripts/clean.sh && ./scripts/setup.sh
  post_package: npm prune --production
```

### Pre-deploy gate and post-deploy smoke test

```yaml
version: 1
project:
  name: my-app
hooks:
  pre_deploy: ./scripts/check-migration.sh
  post_deploy: ./scripts/smoke-test.sh
```

If `check-migration.sh` exits non-zero the deploy stage is skipped.
`smoke-test.sh` runs after a successful deploy; if it fails the deploy
result is unchanged but the failure surfaces in logs.

### Notify external dashboard after release

```yaml
version: 1
project:
  name: my-app
hooks:
  post_release: curl -X POST -d "{\"version\":\"$BRIK_APP_VERSION\"}" https://api.example.com/track
```

## See also

- [`overview.md`](../overview.md) - declarative model
- [`reference/release.md`](release.md) - `BRIK_APP_VERSION` semantics
- [`reference/deploy.md`](deploy.md) - deploy stage lifecycle
- File-based hooks under `.brik/hooks/` (handled by the Bash runtime, not by `brik.yml`)
