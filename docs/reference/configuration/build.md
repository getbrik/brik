# `build`

> Select how the application is compiled or assembled during the Build stage.

**Section:** `build` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/build`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Tell Brik how to turn your source into a build artifact.

The whole section is optional. With no `build` block, Brik runs the stack's default build command, so a typical project never needs to configure it.

When you do need control, you can pin the build tool or supply an exact command.

## What it does

Brik resolves the build command using its canonical three-tier order:

- **Tier 1 (`command`)**: when `build.command` is set, it runs verbatim from `BRIK_WORKSPACE` and `build.tool` is ignored.

- **Tier 2 (`tool`)**: when only `build.tool` is set, the active stack module emits that tool's standard build invocation.

- **Tier 3 (stack default)**: with neither field set, the stack module infers the tool from lock and marker files and runs the per-stack default command.

## When it runs

The Build stage runs on every CI pipeline, after Init and Release.

Its artifact is what the parallel quality stages and the Package stage downstream consume, so Build always executes before them.

## How to configure

Set a `tool` to switch package manager, or a `command` for full control; otherwise omit the section.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `build.command` | `string` | -- |
| `build.tool` | `string` | -- |

- **`build.command`**

  Build command to execute. Overrides both tool selection and stack defaults (Tier 1).

- **`build.tool`**

  Build tool to use (e.g. npm, yarn, pnpm, maven, gradle, poetry, uv, pip, pipenv, cargo, dotnet). Overrides auto-detection from lock/marker files (Tier 2). Ignored when command is set.


*Example*

```yaml
build:
  command: mvn package -DskipTests
  tool: pnpm
```

<!-- END AUTO-GENERATED -->

`build.command` is `eval`-ed from `BRIK_WORKSPACE` (Tier 1). When unset the stack module derives a command from `build.tool` (Tier 2) or from lock/marker files (Tier 3). See [`overview.md`](overview.md) for the cross-cutting tier rule.

### Stack-aware tool values

`build.tool` is free-form, but only a known set is interpreted by the stack modules:

| Stack | Recognised `build.tool` values |
|-------|--------------------------------|
| `node` | `npm`, `yarn`, `pnpm` |
| `python` | `uv`, `poetry`, `pipenv`, `pip` |
| `java` | `maven`, `gradle` |
| `rust` | `cargo` |
| `dotnet` | `dotnet` |

Any other value is forwarded to the stack module verbatim and may be ignored.

### Examples

Pin the tool, keep the stack default command. Forces `pnpm run build` even if the lock file would otherwise resolve to `npm` or `yarn`:

```yaml
version: 1
project:
  name: my-lib
  stack: node
build:
  tool: pnpm
```

Custom command (Tier 1). The command runs verbatim from `BRIK_WORKSPACE`; `build.tool`, if also set, is ignored:

```yaml
version: 1
project:
  name: my-app
  stack: java
build:
  command: mvn package -DskipTests
```

Multi-flag custom build. Any shell-valid command is accepted:

```yaml
version: 1
project:
  name: my-app
  stack: rust
build:
  command: cargo build --release --features prod
```

## See also

- [`project`](project.md) - `stack` and `stack_version` selecting the runner image
- [`test`](test.md) - the test stage shares the tool/stack-default model
- [`overview.md`](overview.md) - tier resolution
- [`stacks/node.md`](stacks/node.md), [`python.md`](stacks/python.md), [`java.md`](stacks/java.md), [`rust.md`](stacks/rust.md), [`dotnet.md`](stacks/dotnet.md) - per-stack defaults
