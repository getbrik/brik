# `security`

> Configure the security-scanning stages: SAST, dependency and secret scanning,
> license compliance, and container image scanning.

**Section:** `security` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/security`](../../../schemas/config/v1/brik.schema.json)

## What it is for

Catch vulnerabilities, leaked secrets, and license problems before an artifact
is published or deployed, and decide what severity blocks the build.

You almost never need to configure this section. With no overrides, each stage
picks a stack-aware default tool (for example `semgrep` for SAST, `osv-scanner`
for dependencies) and uses the `high` threshold to decide what fails.

## What it does

- Runs static application security testing (SAST), with opt-in Infrastructure as
  Code scanning when `security.iac` is set.
- Scans dependencies for known vulnerabilities, scans for committed secrets, and
  checks license compliance, optionally emitting an SBOM.
- Scans the packaged container image for image-level vulnerabilities.
- Fails a stage when a finding's severity meets or exceeds the resolved
  threshold. Lower-severity findings are reported but do not block.

## When it runs

This section drives three CI-visible stages.

SAST and Scan (dependency, secret, license) run after Build, in parallel with
the Test and Lint branches. They always run.

Container Scan runs after the Package stage, against the image Package produced.

## How to configure

The whole section is optional. Each field's type and default is in the table;
its description follows below.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
| Field | Type | Default |
|-------|------|---------|
| `security.severity_threshold` | enum (`critical`, `high`, `medium`, `low`) | -- |

- **`security.severity_threshold`**

  Global minimum vulnerability severity that causes the security stage to fail. Vulnerabilities below this level are reported but do not block the pipeline.


### `security.sast`

Static application security testing configuration.

| Field | Type | Default |
|-------|------|---------|
| `security.sast.command` | `string` | -- |
| `security.sast.tool` | `string` | -- |
| `security.sast.ruleset` | `string` | -- |
| `security.sast.output_format` | enum (`sarif`) | -- |
| `security.sast.output_path` | `string` | -- |

- **`security.sast.command`**

  SAST command to execute. Overrides tool selection (Tier 1).

- **`security.sast.tool`**

  SAST tool to use (e.g. semgrep, sonarqube, codeql). Overrides auto-detection (Tier 2).

- **`security.sast.ruleset`**

  Ruleset or profile for the SAST tool (e.g. auto, p/security-audit).

- **`security.sast.output_format`**

  Format of the SAST report produced for pipeline-report business aggregation. Currently only sarif is supported.

- **`security.sast.output_path`**

  Path (relative to the workspace) where the SAST tool writes its report. Defaults to target/sast.sarif.


*Example*

```yaml
security:
  sast:
    tool: semgrep
    ruleset: p/security-audit
```

### `security.deps`

Dependency vulnerability scanning configuration.

| Field | Type | Default |
|-------|------|---------|
| `security.deps.command` | `string` | -- |
| `security.deps.severity` | enum (`critical`, `high`, `medium`, `low`) | -- |
| `security.deps.tool` | `string` | -- |
| `security.deps.output_path` | `string` | -- |

- **`security.deps.command`**

  Dependency scan command. Overrides tool-based scanning (Tier 1).

- **`security.deps.severity`**

  Minimum severity level that causes the dependency scan to fail.

- **`security.deps.tool`**

  Dependency scanning tool to use (e.g. npm-audit, pip-audit, osv-scanner).

- **`security.deps.output_path`**

  Path (relative to the workspace) where the dependency scan SARIF report is written. Defaults to target/scan.sarif.


#### `security.deps.sbom`

Software Bill of Materials configuration emitted alongside the dependency scan.

| Field | Type | Default |
|-------|------|---------|
| `security.deps.sbom.enabled` | `boolean` | -- |
| `security.deps.sbom.format` | enum (`cyclonedx-1-5`) | -- |
| `security.deps.sbom.output_path` | `string` | -- |

- **`security.deps.sbom.enabled`**

  Whether to produce an SBOM during the scan stage.

- **`security.deps.sbom.format`**

  SBOM serialization format. Currently only CycloneDX 1.5 JSON is supported.

- **`security.deps.sbom.output_path`**

  Path (relative to the workspace) where the SBOM is written. Defaults to target/sbom.cdx.json.


### `security.secrets`

Secret scanning configuration.

| Field | Type | Default |
|-------|------|---------|
| `security.secrets.command` | `string` | -- |
| `security.secrets.tool` | `string` | -- |
| `security.secrets.output_path` | `string` | -- |

- **`security.secrets.command`**

  Secret scan command to execute.

- **`security.secrets.tool`**

  Secret scanning tool to use (e.g. gitleaks, trufflehog).

- **`security.secrets.output_path`**

  Path (relative to the workspace) where the secret scan SARIF report is written. Defaults to target/secret.sarif.


### `security.license`

License compliance checking configuration.

| Field | Type | Default |
|-------|------|---------|
| `security.license.allowed` | `string` | -- |
| `security.license.denied` | `string` | -- |

- **`security.license.allowed`**

  Comma-separated list of allowed licenses.

- **`security.license.denied`**

  Comma-separated list of denied licenses.


*Example*

```yaml
security:
  license:
    allowed: MIT,Apache-2.0,BSD-3-Clause
```

### `security.container`

Container image vulnerability scanning configuration.

| Field | Type | Default |
|-------|------|---------|
| `security.container.image` | `string` | -- |
| `security.container.severity` | enum (`critical`, `high`, `medium`, `low`) | -- |

- **`security.container.image`**

  Container image to scan.

- **`security.container.severity`**

  Minimum severity level that causes the container scan to fail.


### `security.iac`

Infrastructure as Code scanning configuration.

| Field | Type | Default |
|-------|------|---------|
| `security.iac.command` | `string` | -- |
| `security.iac.tool` | `string` | -- |

- **`security.iac.command`**

  IaC scan command to execute.

- **`security.iac.tool`**

  IaC scanning tool to use (e.g. checkov, tfsec).


*Example*

```yaml
security:
  iac:
    tool: checkov
```

<!-- END AUTO-GENERATED -->

When both `license.allowed` and `license.denied` are set, `denied` is checked
first. The IaC scan runs only when `security.iac.command` or `security.iac.tool`
is set.

### Severity semantics

A finding fails the stage when its severity is greater than or equal to the
resolved threshold. The threshold is resolved in this order, lowest precedence
first:

1. **Per-section**: `security.deps.severity`, `security.container.severity`.
2. **Global**: `security.severity_threshold`.
3. **Built-in default**: `high`.

The ordering of severities is `critical > high > medium > low`. Omit the section
entirely and you get `semgrep` (SAST), `osv-scanner` plus `gitleaks` (Scan), and
the default container scan, all failing on `high` or `critical` findings.

### Examples

Per-field examples are under each field above. These are whole-section scenarios
that those do not show.

Pin the SAST tool with a custom ruleset:

```yaml
security:
  sast:
    tool: semgrep
    ruleset: p/security-audit
```

Per-section thresholds. `deps` blocks only on `critical`, `container` blocks on
`medium` or above, and everything else uses the global `high`:

```yaml
security:
  severity_threshold: high
  deps:
    severity: critical
  container:
    severity: medium
```

License allow-list. Only the listed licenses pass compliance:

```yaml
security:
  license:
    allowed: MIT,Apache-2.0,BSD-3-Clause
```

## See also

- [`quality`](quality.md) - lint, format, type check (parallel branch)
- [`package`](package.md) - the container image fed to `security.container`
- [Fixed flows](../../concepts/fixed-flows.md) - where SAST, Scan, and Container Scan sit in the flow
- [`brik.yml` reference](README.md) - all top-level sections
