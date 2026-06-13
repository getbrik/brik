# `quality` configuration

> Schema source: [`brik.schema.json#$defs/quality`](../../../schemas/config/v1/brik.schema.json)

The `quality` section drives the lint stage, which runs three
independent checks: linting, formatting, and (optional) type checking.
Each sub-section follows the same Tier 1 (`command`) / Tier 2 (`tool`) /
Tier 3 (stack default) pattern as `build` and `test`.

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `quality.lint`

Linting configuration.

| Field | Type | Default |
|-------|------|---------|
| `quality.lint.enabled` | `boolean` | `true` |
| `quality.lint.command` | `string` | -- |
| `quality.lint.tool` | `string` | -- |
| `quality.lint.config` | `string` | -- |
| `quality.lint.fix` | `boolean` | `false` |

- **`quality.lint.enabled`**

  DEPRECATED. The runtime no longer honours this key: lint always runs. Init emits a one-shot deprecation warning when 'false' is detected. The key is kept in the schema so legacy brik.yml files keep validating during the migration window; remove it from your config when convenient.

- **`quality.lint.command`**

  Lint command to execute. Overrides tool-based and stack-default lint commands (Tier 1).

- **`quality.lint.tool`**

  Lint tool to use (e.g. eslint, biome, oxlint, checkstyle, ruff, flake8, pylint, clippy, dotnet-format). Overrides the stack default (Tier 2).

- **`quality.lint.config`**

  Path to the lint configuration file (e.g. .eslintrc.yml).

- **`quality.lint.fix`**

  Whether to run the linter in auto-fix mode.


### `quality.format`

Code formatting configuration.

| Field | Type | Default |
|-------|------|---------|
| `quality.format.command` | `string` | -- |
| `quality.format.tool` | `string` | -- |
| `quality.format.check` | `boolean` | `false` |

- **`quality.format.command`**

  Format check command to execute. Overrides tool-based and stack-default format commands (Tier 1).

- **`quality.format.tool`**

  Formatter to use (e.g. prettier, biome, ruff format, black, rustfmt, dotnet-format). Overrides the stack default (Tier 2).

- **`quality.format.check`**

  Whether to run the formatter in check mode (fail if files would be reformatted) rather than applying changes.


### `quality.type_check`

Type checking configuration.

| Field | Type | Default |
|-------|------|---------|
| `quality.type_check.command` | `string` | -- |
| `quality.type_check.tool` | `string` | -- |

- **`quality.type_check.command`**

  Type check command to execute. Overrides tool selection (Tier 1).

- **`quality.type_check.tool`**

  Type checker to use (e.g. tsc, mypy, pyright). Overrides auto-detection (Tier 2).


### `quality.findings`

Findings management policy. Selects the built-in preset that decides which findings fail the build vs. are ignored with reason. Org-wide exception lists are configured separately via the referential.s Policy document (an org-owned brik-policy.yml).

| Field | Type | Default |
|-------|------|---------|
| `quality.findings.policy` | enum (`pragmatic`, `strict`, `permissive`) | `pragmatic` |

- **`quality.findings.policy`**

  Built-in policy preset. pragmatic (default): ignores findings without an upstream fix or below the severity floor; fails the rest. strict: fails every finding at or above the severity floor, including no-fix entries. permissive: fails only critical findings that already have a fix.


<!-- END AUTO-GENERATED -->

The type-check sub-stage runs only when `quality.type_check.command` or
`quality.type_check.tool` is set. There is no Tier 3 default for it.

### Runtime status of each field

A few fields are accepted by the schema but are **not yet consumed** by
the runtime. They pass validation but do not change pipeline behaviour.

| Field | Status |
|-------|--------|
| `quality.lint.enabled` | **deprecated, not consumed** -- lint always runs; Init emits a one-shot warning when `false` is detected |
| `quality.lint.command` | wired (Tier 1) |
| `quality.lint.tool` | wired (Tier 2) |
| `quality.lint.config` | **accepted, not consumed** -- the linter discovers its own config file from disk |
| `quality.lint.fix` | **accepted, not consumed** -- linters always run in check mode |
| `quality.format.command` | wired (Tier 1) |
| `quality.format.tool` | wired (Tier 2) |
| `quality.format.check` | **accepted, not consumed** -- formatters always run in check mode anyway |
| `quality.type_check.command` | wired (Tier 1) |
| `quality.type_check.tool` | wired (Tier 2) |

## Stack defaults

| Stack | Lint default | Format default |
|-------|--------------|----------------|
| `node` | `eslint` | `prettier` |
| `python` | `ruff` | `ruff format` |
| `java` | `checkstyle` | `google-java-format` (declared, not yet implemented) |
| `rust` | `clippy` | `rustfmt` |
| `dotnet` | `dotnet-format` | `dotnet-format` |

When the stack default tool is missing on the runner, Brik exits with
`BRIK_EXIT_MISSING_DEP` rather than silently skipping.

## Examples

### Defaults (omit the section)

```yaml
version: 1
project:
  name: my-app
  stack: node
```

Runs `eslint` and `prettier` with stack defaults. No type check.

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
- [`overview.md`](overview.md) - tier resolution
- [`stacks/`](stacks) - per-stack defaults
