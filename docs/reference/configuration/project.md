# `project`

> [!NOTE]
> Declare the application's identity and which stack toolchain the pipeline runs on.

**Section:** `project` (required) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#properties/project`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Give the application a name and tell Brik which technology stack it is built with.

`project.name` is the only required field in `brik.yml` apart from the top-level `version`. Everything else in the section is optional and has a working default.

The stack and stack version decide which runner image the pipeline uses, so every stage runs with the right toolchain available.

## What it does

- Labels the build in logs, notifications, and artifact names from `project.name`.

- Selects the runner image from `project.stack` and `project.stack_version`. When the stack is omitted, Brik auto-detects it from marker files in the repository.

- Resolves a service root in monorepos from `project.root`, so each service can carry its own `brik.yml`.

- Loads project-level environment variables from `project.env` (or an auto-detected `brik.env` at the repo root). Existing environment variables, such as CI secrets, always take precedence over file entries.

## When it runs

The `project` section is read on every pipeline run, during Init, before any stage executes.

It does not drive a stage of its own. Instead it sets the execution context (name, runner image, working directory, env file) that the whole flow depends on.

## How to configure

`project.name` is required; the rest is optional with auto-detection and sensible defaults.

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

  - **`node`**: Node.js (JavaScript or TypeScript)
  - **`java`**: Java on the JVM (Maven or Gradle)
  - **`python`**: Python
  - **`dotnet`**: .NET (C#)
  - **`rust`**: Rust (Cargo)

- **`project.stack_version`**

  Stack version for runner image selection (e.g. '22' for node, '21' for java). When omitted, uses the default version.

- **`project.root`**

  Relative path to the service root directory. Used in monorepos where each service has its own brik.yml.

- **`project.env`**

  Path to the project-level env file (KEY=VALUE format), relative to the project root. Optional. When omitted, Brik auto-detects 'brik.env' at the repo root. Existing environment variables (CI secrets, etc.) take precedence over file entries.


*Example*

```yaml
project:
  name: orders-api
  stack: node
  stack_version: 22
  root: services/api
  env: services/api/.env.ci
```

<!-- END AUTO-GENERATED -->

### Stack auto-detection

When `project.stack` is omitted, Brik infers it from marker files.

| Marker file | Detected stack |
|-------------|----------------|
| `package.json` | `node` |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | `java` |
| `requirements.txt`, `setup.py`, `pyproject.toml` | `python` |
| `Cargo.toml` | `rust` |
| `*.csproj`, `*.sln` | `dotnet` |

If no marker is present the stack stays empty and stage logic falls back to the base runner image (`brik-runner-base:latest`).

### Stack versions

`project.stack_version` is a free-form string matched against the runner image tag. The supported tags are published in [`brik-images/versions.json`](https://github.com/getbrik/brik-images/blob/main/versions.json).

| Stack | Supported `stack_version` values |
|-------|----------------------------------|
| `node` | `"22"`, `"24"` |
| `python` | `"3.13"`, `"3.14"` |
| `java` | `"21"`, `"25"` |
| `rust` | `"1"` |
| `dotnet` | `"9.0"`, `"10.0"` |

Always quote numeric versions to keep them as strings (`"3.13"`, not `3.13`); the schema rejects numeric values.

### The top-level `version` key

The top-level `version` key declares the schema major version. It is a singleton `const: 1`; any other value fails validation at `brik validate` and at the `init` stage (exit code 7).

A future schema bump (breaking changes) will introduce `version: 2` and a parallel `schemas/config/v2/`. Until then, `1` is the only legal value.

### Examples

Pinned stack and version. Skip auto-detection and force a Java 21 runner image:

```yaml
version: 1
project:
  name: my-java-app
  stack: java
  stack_version: "21"
```

Monorepo service with a project-level env file. `root` is interpreted relative to the repository root; `env` is interpreted relative to `root` (or to the repository root when `root` is unset):

```yaml
version: 1
project:
  name: api
  stack: node
  stack_version: "22"
  root: services/api
  env: services/api/.env.ci
```

## See also

- [`overview.md`](overview.md) - declarative model and three-tier resolution
- [`build`](build.md) - how `stack`/`stack_version` flow into the build stage
- [`stacks/node.md`](stacks/node.md), [`python.md`](stacks/python.md), [`java.md`](stacks/java.md), [`rust.md`](stacks/rust.md), [`dotnet.md`](stacks/dotnet.md) - per-stack notes
- [`brik.yml` reference](README.md) - all top-level sections
