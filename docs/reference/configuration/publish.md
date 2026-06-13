# `publish`

> [!NOTE]
> Push the packaged artifact to one or more package registries (npm, Docker,
> Maven, PyPI, Cargo, NuGet).

**Section:** `publish` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/publish`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Distribute your build output to the registries your consumers pull from.

Each ecosystem has its own sub-object (`npm`, `docker`, `maven`, `pypi`,
`cargo`, `nuget`). Declare as many as you need. Each target is independent and
entirely optional.

## What it does

- Publishes the built artifact to each declared registry target after the local
  artifact build succeeds.
- Reads every credential from a CI environment variable named by a `*_var`
  field, never from a value stored in `brik.yml`.
- Skips a target whose `*_var` points to an unset variable, with a warning. The
  pipeline does not fail.
- Falls back to `package.docker.image` for `publish.docker.image`, and to
  `BRIK_APP_VERSION` (or the commit SHA) for `publish.docker.tags`, when those
  are omitted.

## When it runs

Publishing happens inside the Package stage, after the local artifact build
succeeds. The Package stage runs after Build once Lint, SAST, Scan, and Test
have all completed, on a tag push by default (or whenever `package.trigger`
matches).

## The `*_var` convention

Every credential lives in a CI environment variable. `brik.yml` carries the
**name** of that variable, never its value:

```yaml
publish:
  npm:
    token_var: NPM_TOKEN
```

The runner reads `$NPM_TOKEN` at publish time. This keeps secrets out of the
repository and lets the same `brik.yml` work across multiple environments by
setting different env values.

## How to configure

Declare a sub-object per ecosystem you publish to. Each field's type and default
is in the table; its description follows below.

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


*Example*

```yaml
publish:
  npm:
    access: public
    token_var: NPM_TOKEN
```

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


*Example*

```yaml
publish:
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
```

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


*Example*

```yaml
publish:
  cargo:
    index: sparse+http://nexus:8081/repository/brik-cargo/
```

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

`publish.docker.image` falls back to `package.docker.image` at runtime when
omitted. `publish.docker.tags` defaults to `BRIK_APP_VERSION` or the commit SHA
when the array is empty.

### Examples

Per-field examples are under each field above. These are whole-section scenarios
that those do not show.

Docker image to GHCR, reusing the packaged image. `publish.docker.image` is
omitted, so the runtime falls back to `package.docker.image`:

```yaml
package:
  docker:
    image: ghcr.io/org/app
publish:
  docker:
    registry: ghcr.io
    username_var: GHCR_USER
    password_var: GHCR_TOKEN
```

Maven to a private repository:

```yaml
publish:
  maven:
    repository: https://nexus.example.com/repository/maven-releases/
    username_var: MAVEN_USERNAME
    password_var: MAVEN_PASSWORD
```

Private Cargo registry, which needs a sparse index URL:

```yaml
publish:
  cargo:
    registry: brik-cargo
    index: sparse+http://nexus:8081/repository/brik-cargo/
    token_var: CARGO_TOKEN
```

Multiple targets in one config. The same run publishes both an npm package and a
Docker image:

```yaml
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

- [`package`](package.md) - the build that feeds publish
- [`release`](release.md) - `BRIK_APP_VERSION` semantics that drive tag choice
- [Fixed flows](../../concepts/fixed-flows.md) - where publishing sits in the Package stage
- [`brik.yml` reference](README.md) - all top-level sections
