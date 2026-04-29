# `publish` configuration

> Schema source: [`brik.schema.json#$defs/publish`](../../../schemas/config/v1/brik.schema.json)

The `publish` section declares one or more registry targets. The
package stage triggers each declared target after the local artifact
build succeeds. Each target is independent and entirely optional.

## The `*_var` convention

Every credential lives in a CI environment variable. `brik.yml` carries
the **name** of that variable, never its value:

```yaml
publish:
  npm:
    token_var: NPM_TOKEN
```

The runner reads `$NPM_TOKEN` at publish time. This keeps secrets out
of the repository and lets the same `brik.yml` work across multiple
environments by setting different env values.

A target whose `*_var` field points to an unset variable is skipped
with a warning -- the pipeline does not fail.

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `publish.npm`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `publish.npm.registry` | string | `https://registry.npmjs.org` | npm registry URL. |
| `publish.npm.tag` | string | `latest` | Distribution tag for the published package. |
| `publish.npm.access` | enum (`public`, `restricted`) | -- | Package access level for scoped packages. |
| `publish.npm.token_var` | string | -- | Name of the environment variable holding the npm auth token. Never put the token value here. |

### `publish.docker`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `publish.docker.image` | string | -- | Full image name including registry and repository (e.g. ghcr.io/org/app). |
| `publish.docker.registry` | string | -- | Container registry URL for docker login. |
| `publish.docker.tags` | array of strings | -- | List of tags to push. If empty, uses BRIK_VERSION. |
| `publish.docker.username_var` | string | -- | Name of the environment variable holding the registry username. |
| `publish.docker.password_var` | string | -- | Name of the environment variable holding the registry password or token. |

### `publish.maven`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `publish.maven.repository` | string | -- | Maven repository URL. |
| `publish.maven.username_var` | string | -- | Name of the environment variable holding the repository username. |
| `publish.maven.password_var` | string | -- | Name of the environment variable holding the repository password. |

### `publish.pypi`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `publish.pypi.repository` | string | `https://upload.pypi.org/legacy/` | PyPI repository URL. |
| `publish.pypi.token_var` | string | -- | Name of the environment variable holding the PyPI API token. |

### `publish.cargo`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `publish.cargo.registry` | string | `crates-io` | Cargo registry name. |
| `publish.cargo.index` | string | -- | Sparse index URL for the registry (e.g. sparse+http://nexus:8081/repository/brik-cargo/). Required for private registries. |
| `publish.cargo.token_var` | string | -- | Name of the environment variable holding the registry API token. |

### `publish.nuget`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `publish.nuget.source` | string | `https://api.nuget.org/v3/index.json` | NuGet source URL. |
| `publish.nuget.token_var` | string | -- | Name of the environment variable holding the NuGet token or API key. |

<!-- END AUTO-GENERATED -->

`publish.docker.image` falls back to `package.docker.image` at runtime
when omitted. `publish.docker.tags` defaults to `BRIK_APP_VERSION` or
the commit SHA when the array is empty.

## Examples

### npm public package

```yaml
version: 1
project:
  name: my-lib
  stack: node
publish:
  npm:
    access: public
    token_var: NPM_TOKEN
```

### Docker image to GHCR

```yaml
version: 1
project:
  name: my-app
  stack: node
package:
  docker:
    image: ghcr.io/org/app
publish:
  docker:
    registry: ghcr.io
    username_var: GHCR_USER
    password_var: GHCR_TOKEN
```

`publish.docker.image` is omitted; the runtime falls back to
`package.docker.image`.

### Maven to a private repository

```yaml
version: 1
project:
  name: my-lib
  stack: java
publish:
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
    username_var: MAVEN_USERNAME
    password_var: MAVEN_PASSWORD
```

### PyPI

```yaml
version: 1
project:
  name: my-lib
  stack: python
publish:
  pypi:
    token_var: PYPI_API_TOKEN
```

### Private Cargo registry

```yaml
version: 1
project:
  name: my-crate
  stack: rust
publish:
  cargo:
    registry: brik-cargo
    index: sparse+http://nexus:8081/repository/brik-cargo/
    token_var: CARGO_TOKEN
```

### NuGet

```yaml
version: 1
project:
  name: my-lib
  stack: dotnet
publish:
  nuget:
    token_var: NUGET_TOKEN
```

### Multiple targets in one config

```yaml
version: 1
project:
  name: polyglot
  stack: node
package:
  docker:
    image: ghcr.io/org/polyglot
publish:
  npm:
    token_var: NPM_TOKEN
  docker:
    registry: ghcr.io
    username_var: GHCR_USER
    password_var: GHCR_TOKEN
```

## See also

- [`reference/package.md`](package.md) - the build that feeds publish
- [`reference/release.md`](release.md) - `BRIK_APP_VERSION` semantics that drive tag choice
- [`overview.md`](../overview.md) - declarative model
