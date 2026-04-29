# `package` configuration

> Schema source: [`brik.schema.json#$defs/package`](../../../schemas/config/v1/brik.schema.json)

The `package` stage builds a release artifact from the previously built
sources. Only Docker image packaging is currently wired; the section
key is reserved for future package types.

When `package.docker.image` is unset the package stage logs `skipping
package stage` and returns 0 -- the rest of the pipeline (deploy,
notify) still runs.

## Quick reference

### `package.docker`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `package.docker.image` | string | -- | Full image name including registry and repository (e.g. `registry.example.com/my-service`). When unset the package stage is skipped. |
| `package.docker.dockerfile` | string | `Dockerfile` | Path to the Dockerfile, relative to `BRIK_WORKSPACE`. |
| `package.docker.context` | string | `.` (the workspace root) | Build context path. |
| `package.docker.platforms` | array of strings | -- | Target platforms for multi-arch builds (e.g. `linux/amd64`, `linux/arm64`). Accepted by the schema but not yet consumed by the build wrapper. |
| `package.docker.build_args` | object (string -> string) | -- | Build-time arguments passed as `--build-arg KEY=VALUE`. |

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
default so the subsequent `publish.docker` stage can push it.

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
gap -- track it via a future chantier.

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
- [`overview.md`](../overview.md) - declarative model
