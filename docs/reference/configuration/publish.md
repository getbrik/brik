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

Publish to npm registry.

| Field | Type | Default |
|-------|------|---------|
| `publish.npm.registry` | `string` | `https://registry.npmjs.org` |
| `publish.npm.tag` | `string` | `latest` |
| `publish.npm.access` | enum (`public`, `restricted`) | -- |
| `publish.npm.token_var` | `string` | -- |

- **`publish.npm.registry`**

  npm registry URL.

- **`publish.npm.tag`**

  Distribution tag for the published package.

- **`publish.npm.access`**

  Package access level for scoped packages.

- **`publish.npm.token_var`**

  Name of the environment variable holding the npm auth token. Never put the token value here.


### `publish.docker`

Push Docker image to a container registry.

| Field | Type | Default |
|-------|------|---------|
| `publish.docker.image` | `string` | -- |
| `publish.docker.registry` | `string` | -- |
| `publish.docker.tags` | `array of strings` | -- |
| `publish.docker.username_var` | `string` | -- |
| `publish.docker.password_var` | `string` | -- |

- **`publish.docker.image`**

  Full image name including registry and repository (e.g. ghcr.io/org/app).

- **`publish.docker.registry`**

  Container registry URL for docker login.

- **`publish.docker.tags`**

  List of tags to push. If empty, uses BRIK_APP_VERSION.

- **`publish.docker.username_var`**

  Name of the environment variable holding the registry username.

- **`publish.docker.password_var`**

  Name of the environment variable holding the registry password or token.


*Example*

```yaml
publish:
  docker:
    registry: registry.example.com
    username_var: BRIK_PUBLISH_DOCKER_USER
    password_var: BRIK_PUBLISH_DOCKER_PASSWORD
```

### `publish.maven`

Publish to a Maven repository.

| Field | Type | Default |
|-------|------|---------|
| `publish.maven.repository` | `string` | -- |
| `publish.maven.username_var` | `string` | -- |
| `publish.maven.password_var` | `string` | -- |

- **`publish.maven.repository`**

  Maven repository URL.

- **`publish.maven.username_var`**

  Name of the environment variable holding the repository username.

- **`publish.maven.password_var`**

  Name of the environment variable holding the repository password.


### `publish.pypi`

Publish to PyPI or a compatible registry.

| Field | Type | Default |
|-------|------|---------|
| `publish.pypi.repository` | `string` | `https://upload.pypi.org/legacy/` |
| `publish.pypi.token_var` | `string` | -- |

- **`publish.pypi.repository`**

  PyPI repository URL.

- **`publish.pypi.token_var`**

  Name of the environment variable holding the PyPI API token.


### `publish.cargo`

Publish to crates.io or a compatible Cargo registry (e.g. Nexus).

| Field | Type | Default |
|-------|------|---------|
| `publish.cargo.registry` | `string` | `crates-io` |
| `publish.cargo.index` | `string` | -- |
| `publish.cargo.token_var` | `string` | -- |

- **`publish.cargo.registry`**

  Cargo registry name.

- **`publish.cargo.index`**

  Sparse index URL for the registry (e.g. sparse+http://nexus:8081/repository/brik-cargo/). Required for private registries.

- **`publish.cargo.token_var`**

  Name of the environment variable holding the registry API token.


### `publish.nuget`

Publish to NuGet or a compatible feed.

| Field | Type | Default |
|-------|------|---------|
| `publish.nuget.source` | `string` | `https://api.nuget.org/v3/index.json` |
| `publish.nuget.token_var` | `string` | -- |

- **`publish.nuget.source`**

  NuGet source URL.

- **`publish.nuget.token_var`**

  Name of the environment variable holding the NuGet token or API key.


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
- [`overview.md`](overview.md) - declarative model
