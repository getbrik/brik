# `security` configuration

> Schema source: [`brik.schema.json#$defs/security`](../../../schemas/config/v1/brik.schema.json)

The `security` section drives three CI-visible stages that run in
parallel with `quality`:

- **SAST** -- static application security testing, plus opt-in IaC
  scanning when `security.iac` is set.
- **Scan** -- dependency vulnerability scan + secret scan + license
  compliance.
- **Container scan** -- image-level vulnerability scan, runs after
  `package`.

The whole section is optional. With no overrides, each stage applies a
stack-aware default tool (e.g. `semgrep` for SAST, `osv-scanner` for
deps) and uses the global `severity_threshold` (or the per-section
override) to decide what fails the build.

## Quick reference

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.severity_threshold` | enum (`critical`, `high`, `medium`, `low`) | -- | Global minimum vulnerability severity that causes the security stage to fail. Vulnerabilities below this level are reported but do not block the pipeline. |

### `security.sast`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.sast.command` | string | -- | SAST command to execute. Overrides tool selection (Tier 1). |
| `security.sast.tool` | string | -- | SAST tool to use (e.g. semgrep, sonarqube, codeql). Overrides auto-detection (Tier 2). |
| `security.sast.ruleset` | string | -- | Ruleset or profile for the SAST tool (e.g. auto, p/security-audit). |
| `security.sast.output_format` | enum (`sarif`) | -- | Format of the SAST report produced for pipeline-report business aggregation. Currently only sarif is supported. |
| `security.sast.output_path` | string | -- | Path (relative to the workspace) where the SAST tool writes its report. Defaults to target/sast.sarif. |

### `security.deps`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.deps.command` | string | -- | Dependency scan command. Overrides tool-based scanning (Tier 1). |
| `security.deps.severity` | enum (`critical`, `high`, `medium`, `low`) | -- | Minimum severity level that causes the dependency scan to fail. |
| `security.deps.tool` | string | -- | Dependency scanning tool to use (e.g. npm-audit, pip-audit, osv-scanner). |

### `security.secrets`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.secrets.command` | string | -- | Secret scan command to execute. |
| `security.secrets.tool` | string | -- | Secret scanning tool to use (e.g. gitleaks, trufflehog). |

### `security.license`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.license.allowed` | string | -- | Comma-separated list of allowed licenses. |
| `security.license.denied` | string | -- | Comma-separated list of denied licenses. |

### `security.container`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.container.image` | string | -- | Container image to scan. |
| `security.container.severity` | enum (`critical`, `high`, `medium`, `low`) | -- | Minimum severity level that causes the container scan to fail. |

### `security.iac`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.iac.command` | string | -- | IaC scan command to execute. |
| `security.iac.tool` | string | -- | IaC scanning tool to use (e.g. checkov, tfsec). |

<!-- END AUTO-GENERATED -->

When both `license.allowed` and `license.denied` are set, `denied` is
checked first. The IaC stage runs only when `security.iac.command` or
`security.iac.tool` is set.

## Severity semantics

A finding fails the stage when its severity is greater than or equal to
the resolved threshold (lowest precedence first):

1. **Per-section** -- `security.deps.severity`, `security.container.severity`.
2. **Global** -- `security.severity_threshold`.
3. **Built-in default** -- `high`.

The ordering of severities is `critical > high > medium > low`.

## Examples

### Defaults (omit the section)

```yaml
version: 1
project:
  name: my-app
  stack: node
```

Runs `semgrep` (SAST), `osv-scanner` + `gitleaks` (Scan), and the
default container scan after package. All stages fail on `high` or
`critical` findings.

### Tighten the threshold globally

```yaml
version: 1
project:
  name: my-app
  stack: python
security:
  severity_threshold: medium
```

### License allow-list

```yaml
version: 1
project:
  name: my-lib
  stack: node
security:
  license:
    allowed: MIT,Apache-2.0,BSD-3-Clause
```

### Pin SAST tool with a custom ruleset

```yaml
version: 1
project:
  name: my-app
  stack: python
security:
  sast:
    tool: semgrep
    ruleset: p/security-audit
```

### Per-section thresholds

```yaml
version: 1
project:
  name: my-app
  stack: node
security:
  severity_threshold: high
  deps:
    severity: critical
  container:
    severity: medium
```

`deps` blocks only on `critical`; `container` blocks on `medium` or
above; everything else uses the global `high`.

### IaC scan opt-in

```yaml
version: 1
project:
  name: infra
  stack: python
security:
  iac:
    tool: checkov
```

## See also

- [`reference/quality.md`](quality.md) - lint, format, type check (parallel branch)
- [`reference/package.md`](package.md) - the container image fed to `security.container`
- [`overview.md`](../overview.md) - declarative model
