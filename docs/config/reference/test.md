# `test` configuration

> Schema source: [`brik.schema.json#$defs/test`](../../../schemas/config/v1/brik.schema.json)

## Quick reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `test.command` | string | (stack-derived) | Single test command (Tier 1 override). |
| `test.framework` | string | (stack default, see below) | Test framework (Tier 2). |
| `test.coverage.threshold` | integer | `80` | Minimum coverage percentage required. |
| `test.coverage.report` | string | (none) | Path to a Cobertura coverage report file. |
| `test.reports.enabled` | boolean | `false` | Generate test reports (coverage + JUnit). |
| `test.reports.coverage.enabled` | boolean | `true` | Whether to emit coverage when reports are enabled. |
| `test.reports.coverage.format` | enum | `auto` | `lcov`, `cobertura`, `jacoco`, or `auto`. |
| `test.reports.coverage.output_dir` | string | `coverage` | Directory for the coverage report. |
| `test.reports.junit.enabled` | boolean | `true` | Whether to emit JUnit XML when reports are enabled. |
| `test.reports.junit.output_path` | string | `reports/junit.xml` | Path for the JUnit XML report. |

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
