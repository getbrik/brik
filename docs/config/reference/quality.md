# `quality` configuration

> Schema source: [`brik.schema.json#$defs/quality`](../../../schemas/config/v1/brik.schema.json)

The `quality` section drives the lint stage, which runs three
independent checks: linting, formatting, and (optional) type checking.
Each sub-section follows the same Tier 1 (`command`) / Tier 2 (`tool`) /
Tier 3 (stack default) pattern as `build` and `test`.

## Quick reference

### `quality.lint`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `quality.lint.enabled` | boolean | `true` | Skip the lint sub-stage entirely when `false`. |
| `quality.lint.command` | string | (tool-derived) | Explicit lint command (Tier 1). |
| `quality.lint.tool` | string | (stack default) | Lint tool (Tier 2): `eslint`, `biome`, `oxlint`, `checkstyle`, `ruff`, `flake8`, `pylint`, `clippy`, `dotnet-format`, ... |
| `quality.lint.config` | string | -- | Path to the linter's config file (e.g. `.eslintrc.yml`). |
| `quality.lint.fix` | boolean | `false` | Run the linter in auto-fix mode. |

### `quality.format`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `quality.format.command` | string | (tool-derived) | Explicit format command (Tier 1). |
| `quality.format.tool` | string | (stack default) | Formatter (Tier 2): `prettier`, `biome`, `ruff format`, `black`, `rustfmt`, `dotnet-format`, ... |
| `quality.format.check` | boolean | `false` | Check-only mode. Fails when files would be reformatted instead of rewriting them. |

### `quality.type_check`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `quality.type_check.command` | string | -- | Explicit type-check command (Tier 1). |
| `quality.type_check.tool` | string | -- | Type checker (Tier 2): `tsc`, `mypy`, `pyright`, ... |

The type-check sub-stage runs only when `quality.type_check.command` or
`quality.type_check.tool` is set. There is no Tier 3 default.

## Stack defaults

| Stack | Lint default | Format default |
|-------|--------------|----------------|
| `node` | `eslint` | `prettier` |
| `python` | `ruff` | `ruff format` |
| `java` | `checkstyle` | `google-java-format` (declared, not yet implemented) |
| `rust` | `clippy` | `rustfmt` |
| `dotnet` | `dotnet-format` | `dotnet-format` |

When the stack default tool is missing on the runner, Brik exits with
`BRIK_EXIT_MISSING_DEP` rather than silently skipping. See
[`docs/reference.md`](../../reference.md#quality) for the per-tool
contract (config-file fallbacks, skip conditions).

## Examples

### Defaults (omit the section)

```yaml
version: 1
project:
  name: my-app
  stack: node
```

Runs `eslint` and `prettier` with stack defaults. No type check.

### Disable lint entirely

```yaml
version: 1
project:
  name: my-app
  stack: python
quality:
  lint:
    enabled: false
```

The lint sub-stage is skipped; format still runs.

### Auto-fix on lint, format check-only

```yaml
version: 1
project:
  name: my-lib
  stack: node
quality:
  lint:
    tool: eslint
    fix: true
  format:
    tool: prettier
    check: true
```

`eslint --fix` will rewrite files; `prettier --check` will fail the
stage on any drift instead of rewriting.

### Add a TypeScript type check

```yaml
version: 1
project:
  name: my-app
  stack: node
quality:
  type_check:
    tool: tsc
```

The lint stage now runs lint + format + `tsc --noEmit`.

### Custom commands (Tier 1) end-to-end

```yaml
version: 1
project:
  name: my-app
  stack: python
quality:
  lint:
    command: ruff check --select E,F,I src/
  format:
    command: ruff format --check src/
  type_check:
    command: mypy src/
```

## See also

- [`reference/test.md`](test.md) - the test stage shares the tier model
- [`reference/security.md`](security.md) - SAST and dependency scans
- [`overview.md`](../overview.md) - tier resolution
- [`stacks/`](../stacks/) - per-stack defaults
