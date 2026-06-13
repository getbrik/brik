# `hooks`

> Run your own shell commands before or after any pipeline stage.

**Section:** `hooks` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/hooks`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Insert *your own logic around a stage* without changing the stage itself.

A hook is a single inline shell command attached to a stage by name. Use a
`pre_*` hook to prepare or gate a stage, and a `post_*` hook to react to its
result. Typical uses are cleaning a workspace, running a migration check, or
notifying an external dashboard.

This section is optional. With no `hooks` block nothing extra runs.

## What it does

- Runs the `pre_<stage>` command before the stage. A non-zero exit aborts the
  stage.

- Runs the `post_<stage>` command after the stage completes successfully. It
  is best-effort and cannot override the stage's exit code.

- `eval`s the command in the runner's shell with all Brik-exported variables
  (`BRIK_APP_VERSION`, `BRIK_PROJECT_NAME`, `BRIK_WORKSPACE`, ...) in scope.

- Runs alongside file-based hooks at `.brik/hooks/<hook>.sh`. The two
  mechanisms coexist and both fire; the file-based hook runs after the inline
  command, and failure of either path aborts the stage in the `pre_*` case.

- Treats `brik.yml` as trusted project config, the same trust level as the
  project's own code. There is no sandbox.

## When it runs

Each hook fires around the stage it names, so a hook runs only when its stage
runs. A `pre_<stage>` command fires immediately before the stage starts; a
`post_<stage>` command fires immediately after the stage finishes successfully.

There is one hook pair per CI-visible stage (init, release, build, lint, sast,
scan, container_scan, test, package, deploy, notify), letting you attach logic
at any point in the flow.

## How to configure

Each hook value is a single inline shell command; chain commands with `&&` or `;`.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `hooks.pre_init` | `string` | -- |
| `hooks.post_init` | `string` | -- |
| `hooks.pre_release` | `string` | -- |
| `hooks.post_release` | `string` | -- |
| `hooks.pre_build` | `string` | -- |
| `hooks.post_build` | `string` | -- |
| `hooks.pre_lint` | `string` | -- |
| `hooks.post_lint` | `string` | -- |
| `hooks.pre_sast` | `string` | -- |
| `hooks.post_sast` | `string` | -- |
| `hooks.pre_scan` | `string` | -- |
| `hooks.post_scan` | `string` | -- |
| `hooks.pre_container_scan` | `string` | -- |
| `hooks.post_container_scan` | `string` | -- |
| `hooks.pre_test` | `string` | -- |
| `hooks.post_test` | `string` | -- |
| `hooks.pre_package` | `string` | -- |
| `hooks.post_package` | `string` | -- |
| `hooks.pre_deploy` | `string` | -- |
| `hooks.post_deploy` | `string` | -- |
| `hooks.pre_notify` | `string` | -- |
| `hooks.post_notify` | `string` | -- |

- **`hooks.pre_init`**

  Commands executed before the init stage.

- **`hooks.post_init`**

  Commands executed after the init stage completes successfully.

- **`hooks.pre_release`**

  Commands executed before the release stage.

- **`hooks.post_release`**

  Commands executed after the release stage completes successfully.

- **`hooks.pre_build`**

  Commands executed before the build stage.

- **`hooks.post_build`**

  Commands executed after the build stage completes successfully.

- **`hooks.pre_lint`**

  Commands executed before the lint stage.

- **`hooks.post_lint`**

  Commands executed after the lint stage completes successfully.

- **`hooks.pre_sast`**

  Commands executed before the SAST scan.

- **`hooks.post_sast`**

  Commands executed after the SAST scan completes successfully.

- **`hooks.pre_scan`**

  Commands executed before the security scan stage.

- **`hooks.post_scan`**

  Commands executed after the security scan stage completes successfully.

- **`hooks.pre_container_scan`**

  Commands executed before the container scan.

- **`hooks.post_container_scan`**

  Commands executed after the container scan completes successfully.

- **`hooks.pre_test`**

  Commands executed before the test stage.

- **`hooks.post_test`**

  Commands executed after the test stage completes successfully.

- **`hooks.pre_package`**

  Commands executed before the package stage.

- **`hooks.post_package`**

  Commands executed after the package stage completes successfully.

- **`hooks.pre_deploy`**

  Commands executed before the deploy stage.

- **`hooks.post_deploy`**

  Commands executed after the deploy stage completes successfully.

- **`hooks.pre_notify`**

  Commands executed before the notify stage.

- **`hooks.post_notify`**

  Commands executed after the notify stage completes successfully.


*Example*

```yaml
hooks:
  pre_build: ./scripts/clean.sh && ./scripts/setup.sh
  pre_deploy: ./scripts/check-migration.sh
  post_deploy: ./scripts/smoke-test.sh
```

<!-- END AUTO-GENERATED -->

A hook value must be non-empty; empty strings are rejected by the schema.

### Examples

Per-field examples are above. These are whole-section scenarios.

Chain commands around a stage. Clean before build, prune after package:

```yaml
version: 1
project:
  name: my-app
hooks:
  pre_build: ./scripts/clean.sh && ./scripts/setup.sh
  post_package: npm prune --production
```

Gate the deploy and smoke-test it afterwards:

```yaml
version: 1
project:
  name: my-app
hooks:
  pre_deploy: ./scripts/check-migration.sh
  post_deploy: ./scripts/smoke-test.sh
```

If `check-migration.sh` exits non-zero the deploy stage is skipped.
`smoke-test.sh` runs after a successful deploy; if it fails the deploy result
is unchanged but the failure surfaces in logs.

Notify an external dashboard after a release, using an exported variable:

```yaml
version: 1
project:
  name: my-app
hooks:
  post_release: curl -X POST -d "{\"version\":\"$BRIK_APP_VERSION\"}" https://api.example.com/track
```

## See also

- [`release`](release.md) - `BRIK_APP_VERSION` semantics available to hooks
- [`deploy`](deploy.md) - deploy stage lifecycle around `pre_deploy` / `post_deploy`
- [Fixed flows](../../concepts/fixed-flows.md) - the stages each hook pair attaches to
- [`brik.yml` reference](README.md) - all top-level sections
