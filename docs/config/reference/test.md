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
| `test.reports.coverage` | object | -- | Coverage report configuration. |
| `test.reports.junit` | object | -- | JUnit-compatible XML test report configuration. |

<!-- END AUTO-GENERATED -->

## Stack defaults

| Stack | `test.framework` default | Coverage format default (`auto`) |
|-------|-------------------------|----------------------------------|
| `node` | `jest` | `lcov` |
| `python` | `pytest` | `cobertura` |
| `java` | `junit` | `jacoco` |
| `rust` | `cargo test` | `lcov` |
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

### Coverage threshold

```yaml
version: 1
project:
  name: my-app
  stack: node
test:
  coverage:
    threshold: 90
```

When coverage drops below the threshold, the `test` stage fails with
`BRIK_EXIT_CHECK_FAILED` (10).

## Tier semantics

`test.command` (Tier 1) wins over `test.framework` (Tier 2), which wins
over the stack default (Tier 3).

## See also

- [`reference/quality.md`](quality.md) - lint, format, type check
- [`reference/security.md`](security.md) - SAST, dependency scan
- [`stacks/node.md`](../stacks/node.md), [`python.md`](../stacks/python.md), [`java.md`](../stacks/java.md), [`rust.md`](../stacks/rust.md), [`dotnet.md`](../stacks/dotnet.md) - per-stack notes
- [`overview.md`](../overview.md) - three-tier resolution rule
