# `package`

> Build a release artifact (today, a Docker image) from the sources the build
> stage produced.

**Section:** `package` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/package`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Turn your built sources into the immutable artifact the rest of the flow
publishes, scans, and deploys.

Only Docker image packaging is currently wired. The section key is reserved for
future package types.

## What it does

- Builds a Docker image from your `Dockerfile` and build context, then loads it
  into the local Docker daemon so the publish targets in the same stage can push
  it.
- Tags the image with the version computed by the `release` stage
  (`BRIK_APP_VERSION`), falling back to the short commit SHA, then to `latest`.
- Optionally records a browseable registry UI URL so the pipeline report can
  link to the image page.
- Skips itself when `package.docker.image` is unset. The rest of the flow
  (publish, deploy, notify) still runs.

## When it runs

The Package stage runs after Build, once Lint, SAST, Scan, and Test have all
completed.

By default it runs on a tag push. You can broaden that with `package.trigger`,
for example `on-main: true` to package every push to the default branch, or
`on-feature: true` to build a dev image per feature branch.

## How to configure

The whole section is optional. Each field's type and default is in the table;
its description follows below.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `package.trigger`

When the package stage should run. At least one of the flags must be true for the stage to execute. When the entire block is absent, the legacy always-run behaviour is preserved.

| Field | Type | Default |
|-------|------|---------|
| `package.trigger.on-tag` | `boolean` | `true` |
| `package.trigger.on-main` | `boolean` | `false` |
| `package.trigger.on-feature` | `boolean` | `false` |
| `package.trigger.manual` | `boolean` | `false` |

- **`package.trigger.on-tag`**

  Run when the current commit carries a git tag.

- **`package.trigger.on-main`**

  Run on push to the default branch.

- **`package.trigger.on-feature`**

  Run on push to a branch other than the default (typical use: dev images per feature branch).

- **`package.trigger.manual`**

  Run only when the pipeline was triggered manually (BRIK_TRIGGER_MANUAL=true).


### `package.docker`

Docker image build and push configuration.

| Field | Type | Default |
|-------|------|---------|
| `package.docker.image` | `string` | -- |
| `package.docker.dockerfile` | `string` | `Dockerfile` |
| `package.docker.context` | `string` | `.` |
| `package.docker.platforms` | `array of strings` | -- |
| `package.docker.build_args` | `object` | -- |

- **`package.docker.image`**

  Full image name including registry and repository (e.g. registry.example.com/my-service).

- **`package.docker.dockerfile`**

  Path to the Dockerfile relative to the build context.

- **`package.docker.context`**

  Docker build context path.

- **`package.docker.platforms`**

  Target platforms for multi-arch builds (e.g. linux/amd64, linux/arm64).

- **`package.docker.build_args`**

  Docker build arguments passed as --build-arg. Keys and values must be strings.


*Example*

```yaml
package:
  docker:
    image: registry.example.com/orders/orders-api
    dockerfile: services/api/Dockerfile
    context: services/api/
```

### `package.registry`

Metadata about the registry that hosts the published image. Optional; used to enrich the pipeline report.

| Field | Type | Default |
|-------|------|---------|
| `package.registry.ui_url` | `string` | -- |

- **`package.registry.ui_url`**

  Browseable registry UI URL, distinct from the docker push endpoint (Nexus 3 splits these on ports 8081 vs 8082). Surfaced as business.registry.ui_url so the HTML report links to the image page. The BRIK_PACKAGE_REGISTRY_UI_URL env var set on the runner takes precedence over this value.


*Example*

```yaml
package:
  registry:
    ui_url: https://nexus.example.com:8081/#browse/browse:docker-hosted
```

<!-- END AUTO-GENERATED -->

`docker buildx build --load` is preferred when buildx is available on the runner.
Otherwise the wrapper falls back to legacy `docker build` with a warning.
`platforms` is accepted by the schema today but not yet consumed by the build
wrapper, so the multi-arch build is a runtime gap.

`package.registry.ui_url` is purely cosmetic. It lets the report link to the
human-browseable registry page. Many registries expose a push endpoint that
differs from their UI. Nexus 3, for instance, serves the docker API on port 8082
and the web browser on port 8081, so the URL parsed out of `package.docker.image`
is not the one a human would open. The `BRIK_PACKAGE_REGISTRY_UI_URL` env var on
the runner takes precedence over this value. When neither is set, the report
falls back to a best-effort URL derived from the image host.

### Examples

Per-field examples are under each field above. These are whole-section scenarios
that those do not show.

Custom Dockerfile and context for a monorepo. Build only the `services/api`
subtree:

```yaml
package:
  docker:
    image: registry.example.com/api
    dockerfile: services/api/Dockerfile
    context: services/api/
```

Registry with a separate UI host. The image is pushed to `nexus.example.com:8082`
while the report links to the Nexus web UI on port 8081:

```yaml
package:
  docker:
    image: nexus.example.com:8082/my-app
  registry:
    ui_url: https://nexus.example.com:8081/#browse/browse:docker-hosted
```

Build args passed through to `docker build`. `$BRIK_COMMIT_SHORT_SHA` is expanded
by the runner before the build runs:

```yaml
package:
  docker:
    image: registry.example.com/my-service
    build_args:
      NODE_ENV: production
      COMMIT_SHA: $BRIK_COMMIT_SHORT_SHA
```

## See also

- [`publish`](publish.md) - pushing the built image to the registry
- [`release`](release.md) - `BRIK_APP_VERSION` semantics that drive the image tag
- [`security`](security.md) - the container scan stage runs on the built image
- [Fixed flows](../../concepts/fixed-flows.md) - where the Package stage sits in the flow
- [`brik.yml` reference](README.md) - all top-level sections
