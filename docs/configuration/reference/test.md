# `test` configuration

> Schema source: [`brik.schema.json#$defs/test`](../../../schemas/config/v1/brik.schema.json)

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `test.command` | string | -- | Test command to execute. Overrides framework-derived and stack-default commands (Tier 1). |
| `test.framework` | string | -- | Test framework to use. Overrides the stack default (e.g. jest for node, junit for java, pytest for python). |

### `test.coverage`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `test.coverage.threshold` | integer | `80` | Minimum coverage percentage required. |
| `test.coverage.report` | string | -- | Path to the coverage report file (Cobertura XML). |

### `test.reports`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `test.reports.enabled` | boolean | `false` | Whether to produce test reports. Default: false (test runner uses its native defaults). |
| `test.reports.coverage` | object | -- | Coverage report configuration. Gated by the parent `reports.enabled` toggle. |
| `test.reports.junit` | object | -- | JUnit-compatible XML test report configuration. Gated by the parent `reports.enabled` toggle. |

<!-- END AUTO-GENERATED -->

## Runtime status of each field

Several fields above are accepted by the schema but are **not yet
consumed** by the runtime. Setting them does not break validation, but
it does not change pipeline behaviour either.

| Field | Status |
|-------|--------|
| `test.command` | wired -- `eval`'d from `BRIK_WORKSPACE` |
| `test.framework` | wired -- branched per stack (see *Supported framework values* below) |
| `test.coverage.threshold` | wired -- when set, the Test stage exits with `BRIK_EXIT_CHECK_FAILED` (10) if measured coverage is below the threshold. Requires `test.reports.enabled: true` so a coverage report exists; missing or malformed reports never block the pipeline. |
| `test.coverage.report` | **accepted, not consumed** |
| `test.reports.enabled` | wired -- single master flag for coverage + JUnit emission |
| `test.reports.coverage.format` | **decorative** -- the actual format is hardcoded per stack (see table below); setting `jacoco` on a Node project does not produce jacoco |
| `test.reports.coverage.output_dir` | wired -- consumed by stack test commands |
| `test.reports.junit.output_path` | wired -- consumed by stack test commands |

## Supported framework values

Each stack accepts a closed set of framework names; the dispatcher
rejects any other value before the test command is built.

| Stack | Accepted `framework` values |
|-------|------------------------------|
| `node` | `jest`, `vitest`, `npm` |
| `python` | `pytest`, `unittest`, `tox` |
| `java` | `junit`, `maven`, `gradle` (`junit` is treated as Maven) |
| `rust` | `cargo` |
| `dotnet` | `dotnet`, `xunit`, `nunit` (aliases for the same `dotnet test` invocation; the runner is auto-detected from the project's `<PackageReference>`) |

## Stack defaults

| Stack | `test.framework` default | Coverage format produced |
|-------|-------------------------|--------------------------|
| `node` | `jest` | `cobertura` |
| `python` | `pytest` | `cobertura` |
| `java` | `junit` (Maven) | `jacoco` |
| `rust` | `cargo` | `cobertura` (when `cargo-llvm-cov` is available) |
| `dotnet` | `xunit` | `cobertura` |

## Examples

### Minimal (all defaults)

```yaml
version: 1
project:
  name: my-app
  stack: node
test:
  framework: jest
```

### Reports enabled

When `test.reports.enabled` is `true`, Brik injects framework-specific
flags into the test command to produce a Cobertura coverage report and
a JUnit XML report at the documented paths. The CI consumes those
artifacts automatically.

```yaml
version: 1
project:
  name: my-app
  stack: java
test:
  framework: junit
  reports:
    enabled: true
    coverage:
      format: jacoco
      output_dir: target/coverage
    junit:
      output_path: target/junit.xml
```

### Coverage threshold (enforced)

```yaml
version: 1
project:
  name: my-app
  stack: node
test:
  reports:
    enabled: true
  coverage:
    threshold: 90
```

When set, the Test stage compares the parsed coverage percentage against
this value after the test command runs. If the measured coverage is
below the threshold, the stage exits with `BRIK_EXIT_CHECK_FAILED` (10).
The gate runs only when `test.reports.enabled: true` so a coverage
report exists; a missing or malformed report logs a warning and lets
the pipeline continue. A passing-but-undercovered run is escalated to a
failure; a failing test run keeps its own rc rather than being
overwritten by the gate.

## Tier semantics

`test.command` (Tier 1) wins over `test.framework` (Tier 2), which wins
over the stack default (Tier 3).

## See also

- [`reference/quality.md`](quality.md) - lint, format, type check
- [`reference/security.md`](security.md) - SAST, dependency scan
- [`stacks/node.md`](../stacks/node.md), [`python.md`](../stacks/python.md), [`java.md`](../stacks/java.md), [`rust.md`](../stacks/rust.md), [`dotnet.md`](../stacks/dotnet.md) - per-stack notes
- [`overview.md`](../overview.md) - three-tier resolution rule
