# `project` configuration

> Schema source: [`brik.schema.json#properties/project`](../../../schemas/config/v1/brik.schema.json)

The `project` section carries identity. `project.name` is the only
required field in `brik.yml` apart from the top-level `version`.

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `project.name` | `string` | -- |
| `project.stack` | enum (`node`, `java`, `python`, `dotnet`, `rust`) | -- |
| `project.stack_version` | `string` | -- |
| `project.root` | `string` | -- |
| `project.env` | `string` | -- |

- **`project.name`**

  Project name. Used in logs, notifications, and artefact labels.

- **`project.stack`**

  Technology stack. Optional - Brik performs auto-detection from project files (package.json -> node, pom.xml -> java, etc.) when omitted.

- **`project.stack_version`**

  Stack version for runner image selection (e.g. '22' for node, '21' for java). When omitted, uses the default version.

- **`project.root`**

  Relative path to the service root directory. Used in monorepos where each service has its own brik.yml.

- **`project.env`**

  Path to the project-level env file (KEY=VALUE format), relative to the project root. Optional. When omitted, Brik auto-detects 'brik.env' at the repo root. Existing environment variables (CI secrets, etc.) take precedence over file entries.


<!-- END AUTO-GENERATED -->

`project.name` is required (minimum length 1). `project.stack` is
auto-detected from marker files when omitted (see below). `project.env`
defaults to `brik.env` at the repo root when the file exists.

## Stack auto-detection

When `project.stack` is omitted, Brik infers it from marker files.

| Marker file | Detected stack |
|-------------|----------------|
| `package.json` | `node` |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | `java` |
| `requirements.txt`, `setup.py`, `pyproject.toml` | `python` |
| `Cargo.toml` | `rust` |
| `*.csproj`, `*.sln` | `dotnet` |

If no marker is present the stack stays empty and stage logic falls back
to the base runner image (`brik-runner-base:latest`).

## Stack versions

`project.stack_version` is a free-form string matched against the
runner image tag. The supported tags are published in
[`brik-images/versions.json`](https://github.com/getbrik/brik-images/blob/main/versions.json).

| Stack | Supported `stack_version` values |
|-------|----------------------------------|
| `node` | `"22"`, `"24"` |
| `python` | `"3.13"`, `"3.14"` |
| `java` | `"21"`, `"25"` |
| `rust` | `"1"` |
| `dotnet` | `"9.0"`, `"10.0"` |

Always quote numeric versions to keep them as strings (`"3.13"`, not
`3.13`); the schema rejects numeric values.

## Examples

### Minimal

```yaml
version: 1
project:
  name: my-app
```

Stack auto-detected from the repo, default runner image.

### Pinned stack and version

```yaml
version: 1
project:
  name: my-java-app
  stack: java
  stack_version: "21"
```

### Monorepo service with a project-level env file

```yaml
version: 1
project:
  name: api
  stack: node
  stack_version: "22"
  root: services/api
  env: services/api/.env.ci
```

`root` is interpreted relative to the repository root; `env` is
interpreted relative to `root` (or to the repository root when `root` is
unset).

## Version

The top-level `version` key declares the schema major version. It is a
singleton `const: 1`; any other value fails validation at `brik
validate` and at the `init` stage (exit code 7).

```yaml
version: 1
project:
  name: my-app
```

A future schema bump (breaking changes) will introduce `version: 2` and
a parallel `schemas/config/v2/`. Until then, `1` is the only legal
value.

## See also

- [`overview.md`](overview.md) - declarative model and three-tier resolution
- [`reference/build.md`](build.md) - how `stack`/`stack_version` flow into the build stage
- [`stacks/node.md`](stacks/node.md), [`python.md`](stacks/python.md), [`java.md`](stacks/java.md), [`rust.md`](stacks/rust.md), [`dotnet.md`](stacks/dotnet.md) - per-stack notes
