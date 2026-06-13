# `quality`

> Drive the Lint stage: linting, formatting, optional type checking, and the findings policy.

**Section:** `quality` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/quality`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Tell Brik how to check code quality before the artifact is packaged.

The whole section is optional. With no `quality` block, Brik runs each stack's default linter and formatter, so a typical project never needs to configure it.

When you do need control, you can pin the tools, supply exact commands, add a type check, or change which findings fail the build.

## What it does

The Lint stage runs three independent checks: linting, formatting, and (optional) type checking. Each sub-section resolves its command using the canonical three-tier order:

- **Tier 1 (`command`)**: when a sub-section's `command` is set, it runs verbatim and its `tool` is ignored.

- **Tier 2 (`tool`)**: when only a `tool` is set, the active stack module emits that tool's standard invocation.

- **Tier 3 (stack default)**: with neither field set, the stack module runs its default tool. Type checking has no Tier 3 default; it runs only when `quality.type_check.command` or `quality.type_check.tool` is set.

The `quality.findings.policy` preset decides which findings fail the build versus are ignored with a reason.

## When it runs

The Lint stage runs on every CI pipeline, in parallel with Test, SAST, and Scan, after Build.

The Package stage waits on all four and gates on their business outcome, so a finding that the active policy treats as a failure blocks packaging.

## How to configure

Pin a `tool` or `command` per check, add a `type_check` to enable it, and pick a `findings.policy` preset.

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


*Example*

```yaml
quality:
  lint:
    tool: eslint
```

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


*Example*

```yaml
quality:
  format:
    tool: prettier
```

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


*Example*

```yaml
quality:
  type_check:
    tool: tsc
```

### `quality.findings`

Findings management policy. Selects the built-in preset that decides which findings fail the build vs. are ignored with reason. Org-wide exception lists are configured separately via the referential.s Policy document (an org-owned brik-policy.yml).

| Field | Type | Default |
|-------|------|---------|
| `quality.findings.policy` | enum (`pragmatic`, `strict`, `permissive`) | `pragmatic` |

- **`quality.findings.policy`**

  Built-in policy preset. pragmatic (default): ignores findings without an upstream fix or below the severity floor; fails the rest. strict: fails every finding at or above the severity floor, including no-fix entries. permissive: fails only critical findings that already have a fix.


*Example*

```yaml
quality:
  findings:
    policy: strict
```

<!-- END AUTO-GENERATED -->

The type-check sub-stage runs only when `quality.type_check.command` or `quality.type_check.tool` is set. There is no Tier 3 default for it.

### Runtime status of each field

A few fields are accepted by the schema but are **not yet consumed** by the runtime. They pass validation but do not change pipeline behaviour.

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

### Stack defaults

| Stack | Lint default | Format default |
|-------|--------------|----------------|
| `node` | `eslint` | `prettier` |
| `python` | `ruff` | `ruff format` |
| `java` | `checkstyle` | `google-java-format` (declared, not yet implemented) |
| `rust` | `clippy` | `rustfmt` |
| `dotnet` | `dotnet-format` | `dotnet-format` |

When the stack default tool is missing on the runner, Brik exits with `BRIK_EXIT_MISSING_DEP` rather than silently skipping.

### Examples

Auto-fix on lint, format check-only. `eslint --fix` rewrites files; `prettier --check` fails the stage on any drift instead of rewriting:

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

Add a TypeScript type check. The lint stage now runs lint, format, and `tsc --noEmit`:

```yaml
version: 1
project:
  name: my-app
  stack: node
quality:
  type_check:
    tool: tsc
```

Custom commands (Tier 1) end-to-end. Each sub-section's command runs verbatim:

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
