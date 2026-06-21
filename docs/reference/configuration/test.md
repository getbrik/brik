# `test`

> [!NOTE]
> Run the project's automated tests, and optionally enforce a coverage threshold and emit CI reports.

**Section:** `test` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/test`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Tell Brik how to run your test suite.

The whole section is optional. With no `test` block, Brik runs the stack's default framework, so a typical project never needs to configure it.

When you do need control, you can pin the framework, supply an exact command, turn on report generation, or enforce a minimum coverage percentage.

## What it does

Brik resolves the test command using its canonical three-tier order:

- **Tier 1 (`command`)**: when `test.command` is set, it runs verbatim from `BRIK_WORKSPACE` and the framework is ignored.

- **Tier 2 (`framework`)**: when only `test.framework` is set, the active stack module emits that framework's standard invocation.

- **Tier 3 (stack default)**: with neither field set, the stack module runs its default framework.

On top of that:

- With `test.reports.enabled: true`, Brik injects framework-specific flags into the test command to produce a coverage report and a JUnit-compatible XML report at the configured paths, which the CI consumes automatically.

- With `test.coverage.threshold` set, the stage fails when measured coverage falls below the threshold (it requires reports to be enabled so a coverage report exists).

## When it runs

The Test stage runs on every CI pipeline, in parallel with Lint, SAST, and Scan, after Build.

The Package stage waits on all four and gates on their business outcome, so a coverage threshold failure here blocks packaging.

## How to configure

Pin a `framework` or `command`, then optionally enable `reports` and a coverage `threshold`.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `test.command` | `string` | -- |
| `test.framework` | `string` | -- |

- **`test.command`**

  Test command to execute. Overrides framework-derived and stack-default commands (Tier 1).

- **`test.framework`**

  Test framework to use. Overrides the stack default (e.g. jest for node, junit for java, pytest for python).


*Example*

```yaml
test:
  command: npm test -- --runInBand
  framework: jest
```

### `test.coverage`

Test coverage threshold enforcement.

| Field | Type | Default |
|-------|------|---------|
| `test.coverage.threshold` | `integer` | `80` |
| `test.coverage.report` | `string` | -- |

- **`test.coverage.threshold`**

  Minimum coverage percentage required.

- **`test.coverage.report`**

  Path to the coverage report file (Cobertura XML).


*Example*

```yaml
test:
  coverage:
    threshold: 80
```

### `test.reports`

Test report generation. When enabled, Brik injects framework-specific flags into the test command to produce coverage and JUnit-compatible XML reports for the CI to consume.

| Field | Type | Default |
|-------|------|---------|
| `test.reports.enabled` | `boolean` | `false` |

- **`test.reports.enabled`**

  Whether to produce test reports. Default: false (test runner uses its native defaults).


#### `test.reports.coverage`

Coverage report configuration. Gated by the parent `reports.enabled` toggle.

| Field | Type | Default |
|-------|------|---------|
| `test.reports.coverage.format` | enum (`lcov`, `cobertura`, `jacoco`, `auto`) | `auto` |
| `test.reports.coverage.output_dir` | `string` | `coverage` |

- **`test.reports.coverage.format`**

  Coverage report format.

  - **`lcov`**: available value; no stack produces it by default
  - **`cobertura`**: produced by node, rust, python and dotnet
  - **`jacoco`**: produced by java
  - **`auto`** (default): let Brik pick the format from the stack

- **`test.reports.coverage.output_dir`**

  Directory where the coverage report is written. Default: coverage.


*Example*

```yaml
test:
  reports:
    coverage:
      output_dir: target/coverage
```

#### `test.reports.junit`

JUnit-compatible XML test report configuration. Gated by the parent `reports.enabled` toggle.

| Field | Type | Default |
|-------|------|---------|
| `test.reports.junit.output_path` | `string` | `reports/junit.xml` |

- **`test.reports.junit.output_path`**

  Path where the JUnit XML report is written. Default: reports/junit.xml.


*Example*

```yaml
test:
  reports:
    junit:
      output_path: target/junit.xml
```

<!-- END AUTO-GENERATED -->

### Runtime status of each field

Several fields above are accepted by the schema but are **not yet consumed** by the runtime. Setting them does not break validation, but it does not change pipeline behaviour either.

| Field | Status |
|-------|--------|
| `test.command` | wired (`eval`'d from `BRIK_WORKSPACE`) |
| `test.framework` | wired, branched per stack (see *Supported framework values* below) |
| `test.coverage.threshold` | wired: when set, the Test stage exits with `BRIK_EXIT_CHECK_FAILED` (10) if measured coverage is below the threshold. Requires `test.reports.enabled: true` so a coverage report exists; missing or malformed reports never block the pipeline. |
| `test.coverage.report` | **accepted, not consumed** |
| `test.reports.enabled` | wired: single master flag for coverage + JUnit emission |
| `test.reports.coverage.format` | **decorative**: the actual format is hardcoded per stack (see table below); setting `jacoco` on a Node project does not produce jacoco |
| `test.reports.coverage.output_dir` | wired, consumed by stack test commands |
| `test.reports.junit.output_path` | wired, consumed by stack test commands |

### Supported framework values

Each stack accepts a closed set of framework names; the dispatcher rejects any other value before the test command is built.

| Stack | Accepted `framework` values |
|-------|------------------------------|
| `node` | `jest`, `vitest`, `npm` |
| `python` | `pytest`, `unittest`, `tox` |
| `java` | `junit`, `maven`, `gradle` (`junit` is treated as Maven) |
| `rust` | `cargo` |
| `dotnet` | `dotnet`, `xunit`, `nunit` (aliases for the same `dotnet test` invocation; the runner is auto-detected from the project's `<PackageReference>`) |

### Stack defaults

| Stack | `test.framework` default | Coverage format produced |
|-------|-------------------------|--------------------------|
| `node` | `jest` | `cobertura` |
| `python` | `pytest` | `cobertura` |
| `java` | `junit` (Maven) | `jacoco` |
| `rust` | `cargo` | `cobertura` (when `cargo-llvm-cov` is available) |
| `dotnet` | `dotnet` | `cobertura` |

`test.command` (Tier 1) wins over `test.framework` (Tier 2), which wins over the stack default (Tier 3).

### Examples

Reports enabled. Brik injects framework-specific flags to produce a coverage report and a JUnit XML report at the documented paths, which the CI consumes automatically:

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

Coverage threshold (enforced). The stage compares the parsed coverage percentage against this value after the test command runs and exits with `BRIK_EXIT_CHECK_FAILED` (10) when it is too low. The gate runs only when reports are enabled so a report exists; a missing or malformed report logs a warning and lets the pipeline continue. A passing-but-undercovered run is escalated to a failure, while a failing test run keeps its own return code:

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

## See also

- [`reference/quality.md`](quality.md) - lint, format, type check
- [`reference/security.md`](security.md) - SAST, dependency scan
- [`stacks/node.md`](stacks/node.md), [`python.md`](stacks/python.md), [`java.md`](stacks/java.md), [`rust.md`](stacks/rust.md), [`dotnet.md`](stacks/dotnet.md) - per-stack notes
- [`overview.md`](overview.md) - three-tier resolution rule
