# `build` configuration

> Schema source: [`brik.schema.json#$defs/build`](../../../schemas/config/v1/brik.schema.json)

The `build` section selects how the application is compiled or
assembled. The whole section is optional; with no `build` block Brik
runs the stack's default build command.

## Quick reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `build.command` | string | (stack-derived) | Explicit build command (Tier 1). Overrides `tool` and stack defaults. Run via `eval` from `BRIK_WORKSPACE`. |
| `build.tool` | string | (auto-detected from lock/marker files) | Build tool selector (Tier 2). Ignored when `command` is set. |

## Three-tier resolution

The build stage picks its command using the canonical Brik resolution
order:

1. **Tier 1 -- `build.command`** wins when set. `tool` is ignored.
2. **Tier 2 -- `build.tool`** picks the tool inside the active stack
   when `command` is unset. The stack module emits the tool's standard
   build invocation.
3. **Tier 3 -- stack default**. With neither `command` nor `tool`,
   Brik infers the tool from lock files / marker files and runs the
   per-stack default command.

See [`overview.md`](../overview.md) for the cross-cutting tier rule.

## Stack-aware tool values

`build.tool` is free-form, but only a known set is interpreted by the
stack modules:

| Stack | Recognised `build.tool` values |
|-------|--------------------------------|
| `node` | `npm`, `yarn`, `pnpm` |
| `python` | `uv`, `poetry`, `pipenv`, `pip` |
| `java` | `maven`, `gradle` |
| `rust` | `cargo` |
| `dotnet` | `dotnet` |

Any other value is forwarded to the stack module verbatim and may be
ignored.

## Examples

### Defaults (omit the section)

```yaml
version: 1
project:
  name: my-app
  stack: node
```

The Node stack module picks the package manager from
`package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` and runs
`<pm> run build`.

### Pin the tool, keep the stack default command

```yaml
version: 1
project:
  name: my-lib
  stack: node
build:
  tool: pnpm
```

Forces `pnpm run build` even if the lock file would otherwise resolve
to `npm` or `yarn`.

### Custom command (Tier 1)

```yaml
version: 1
project:
  name: my-app
  stack: java
build:
  command: mvn package -DskipTests
```

The custom command runs verbatim from `BRIK_WORKSPACE`. `build.tool`,
if also set, is ignored.

### Multi-flag custom build

```yaml
version: 1
project:
  name: my-app
  stack: rust
build:
  command: cargo build --release --features prod
```

## See also

- [`reference/project.md`](project.md) - `stack` and `stack_version` selecting the runner image
- [`reference/test.md`](test.md) - the test stage shares the tool/stack-default model
- [`overview.md`](../overview.md) - tier resolution
- [`stacks/node.md`](../stacks/node.md), [`python.md`](../stacks/python.md), [`java.md`](../stacks/java.md), [`rust.md`](../stacks/rust.md), [`dotnet.md`](../stacks/dotnet.md) - per-stack defaults
