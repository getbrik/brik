# `security` configuration

> Schema source: [`brik.schema.json#$defs/security`](../../../schemas/config/v1/brik.schema.json)

The `security` section drives three CI-visible stages that run in
parallel with `quality`:

- **SAST** -- static application security testing.
- **Scan** -- dependency vulnerability scan + secret scan + license
  compliance.
- **Container scan** -- image-level vulnerability scan, runs after
  `package`.

A seventh sub-block, `iac`, is reserved for future Infrastructure-as-Code
scanning.

The whole section is optional. With no overrides, each stage applies a
stack-aware default tool (e.g. `semgrep` for SAST, `osv-scanner` for
deps) and uses the global `severity_threshold` (or the per-section
override) to decide what fails the build.

## Quick reference

### `security.sast`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.sast.command` | string | (tool-derived) | Explicit SAST command (Tier 1). |
| `security.sast.tool` | string | `semgrep` | SAST tool (Tier 2): `semgrep`, `sonarqube`, `codeql`, ... |
| `security.sast.ruleset` | string | `auto` | Ruleset or profile (e.g. `p/security-audit`). |

### `security.deps`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.deps.command` | string | (tool-derived) | Explicit dependency scan command (Tier 1). |
| `security.deps.tool` | string | `osv-scanner` (or stack default) | Dep scanner: `osv-scanner`, `npm-audit`, `pip-audit`, ... |
| `security.deps.severity` | enum | (inherits `severity_threshold`) | Per-section threshold: `critical`, `high`, `medium`, `low`. |

### `security.secrets`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.secrets.command` | string | (tool-derived) | Explicit secret scan command (Tier 1). |
| `security.secrets.tool` | string | `gitleaks` | Secret scanner: `gitleaks`, `trufflehog`, ... |

### `security.license`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.license.allowed` | string | -- | Comma-separated allow-list (e.g. `MIT,Apache-2.0,BSD-3-Clause`). |
| `security.license.denied` | string | -- | Comma-separated deny-list (e.g. `GPL-3.0,AGPL-3.0`). |

When both are set, `denied` is checked first.

### `security.container`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.container.image` | string | (falls back to `package.docker.image`) | Image to scan. |
| `security.container.severity` | enum | (inherits `severity_threshold`) | Per-section threshold: `critical`, `high`, `medium`, `low`. |

### `security.iac`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.iac.command` | string | -- | Explicit IaC scan command (Tier 1). |
| `security.iac.tool` | string | -- | IaC scanner: `checkov`, `tfsec`, ... |

The IaC stage runs only when `security.iac.command` or
`security.iac.tool` is set.

### Global threshold

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `security.severity_threshold` | enum | `high` | Minimum vulnerability severity that fails the security stage. Lower-severity findings are reported but do not block. |

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
