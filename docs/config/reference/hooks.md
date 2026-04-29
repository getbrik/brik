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

| Field | Type | Default | Runs |
|-------|------|---------|------|
| `hooks.pre_init` / `hooks.post_init` | string | -- | around the init stage |
| `hooks.pre_release` / `hooks.post_release` | string | -- | around the release stage |
| `hooks.pre_build` / `hooks.post_build` | string | -- | around the build stage |
| `hooks.pre_lint` / `hooks.post_lint` | string | -- | around the lint stage |
| `hooks.pre_sast` / `hooks.post_sast` | string | -- | around the SAST stage |
| `hooks.pre_scan` / `hooks.post_scan` | string | -- | around the dependency / secret scan stage |
| `hooks.pre_container_scan` / `hooks.post_container_scan` | string | -- | around the container scan stage |
| `hooks.pre_test` / `hooks.post_test` | string | -- | around the test stage |
| `hooks.pre_package` / `hooks.post_package` | string | -- | around the package stage |
| `hooks.pre_deploy` / `hooks.post_deploy` | string | -- | around the deploy stage |
| `hooks.pre_notify` / `hooks.post_notify` | string | -- | around the notify stage |

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
