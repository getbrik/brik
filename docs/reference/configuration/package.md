# `package` configuration

> Schema source: [`brik.schema.json#$defs/package`](../../../schemas/config/v1/brik.schema.json)

The `package` stage builds a release artifact from the previously built
sources. Only Docker image packaging is currently wired; the section
key is reserved for future package types.

When `package.docker.image` is unset the package stage logs `skipping
package stage` and returns 0 -- the rest of the pipeline (deploy,
notify) still runs.

## Quick reference

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


### `package.registry`

Metadata about the registry that hosts the published image. Optional; used to enrich the pipeline report.

| Field | Type | Default |
|-------|------|---------|
| `package.registry.ui_url` | `string` | -- |

- **`package.registry.ui_url`**

  Browseable registry UI URL, distinct from the docker push endpoint (Nexus 3 splits these on ports 8081 vs 8082). Surfaced as business.registry.ui_url so the HTML report links to the image page. The BRIK_PACKAGE_REGISTRY_UI_URL env var set on the runner takes precedence over this value.


<!-- END AUTO-GENERATED -->

When `package.docker.image` is unset, the package stage is skipped
(the pipeline still continues with deploy and notify). `platforms` is
accepted by the schema today but not yet consumed by the build wrapper.

## Tagging

The image is tagged with `<image>:<tag>` where `<tag>` is, in order of
preference:

1. `BRIK_APP_VERSION` -- the version computed by the `release` stage.
2. `BRIK_COMMIT_SHORT_SHA` -- the short Git commit SHA when no release
   has run.
3. `latest` -- ultimate fallback.

A typical pipeline produces `registry.example.com/my-service:1.4.2` on
release builds and `registry.example.com/my-service:abc1234` on
non-release builds.

## Build engine

`docker buildx build --load` is preferred when buildx is available on
the runner; otherwise the wrapper falls back to legacy `docker build`
with a warning. The image is loaded into the local Docker daemon by
default so the publish targets, which run later within the same
`package` stage, can push it.

## Registry UI link

`package.registry.ui_url` is purely cosmetic: it lets the pipeline
report link to the human-browseable registry page. Many registries
expose a push endpoint that differs from their UI -- Nexus 3, for
instance, serves the docker API on port 8082 and the web browser on
port 8081 -- so the URL parsed out of `package.docker.image` is not the
one a human would open.

Set it in `brik.yml`, or override it once at the CI level with the
`BRIK_PACKAGE_REGISTRY_UI_URL` env var on the runner (the env var
wins). When neither is set, `business.registry.ui_url` is omitted and
the report falls back to a best-effort URL derived from the image
host.

## Examples

### Minimal docker package

```yaml
version: 1
project:
  name: my-app
  stack: node
package:
  docker:
    image: registry.example.com/my-service
```

Builds `registry.example.com/my-service:<version-or-sha>` from
`Dockerfile` at the workspace root.

### Custom Dockerfile and context (monorepo)

```yaml
version: 1
project:
  name: api
  stack: node
  root: services/api
package:
  docker:
    image: registry.example.com/api
    dockerfile: services/api/Dockerfile
    context: services/api/
```

### Multi-arch (schema-only today)

```yaml
version: 1
project:
  name: my-app
  stack: rust
package:
  docker:
    image: registry.example.com/my-service
    platforms:
      - linux/amd64
      - linux/arm64
```

The schema validates the value, but the multi-arch build is a runtime
gap -- it is not yet implemented.

### Registry with a separate UI host

```yaml
version: 1
project:
  name: my-app
  stack: node
package:
  docker:
    image: nexus.example.com:8082/my-app
  registry:
    ui_url: https://nexus.example.com:8081/#browse/browse:docker-hosted
```

The image is pushed to `nexus.example.com:8082` but the report links
to the Nexus web UI on port 8081.

### Build args

```yaml
version: 1
project:
  name: my-app
  stack: node
package:
  docker:
    image: registry.example.com/my-service
    build_args:
      NODE_ENV: production
      COMMIT_SHA: $BRIK_COMMIT_SHORT_SHA
```

`$BRIK_COMMIT_SHORT_SHA` is expanded by the runner before invoking
`docker build`.

## See also

- [`reference/publish.md`](publish.md) - pushing the built image to the registry
- [`reference/release.md`](release.md) - `BRIK_APP_VERSION` semantics that drive the image tag
- [`reference/security.md`](security.md) - the container scan stage runs on the built image
- [`overview.md`](overview.md) - declarative model
