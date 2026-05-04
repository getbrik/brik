# Brik test fixtures

Real outputs from real tools, captured against real code. Used by ShellSpec
suites under `spec/transverse/sarif_spec.sh`, `spec/transverse/sbom_spec.sh`,
and the lint/sast/scan stage specs.

These fixtures are not synthetic. Replacing or extending them requires running
`scripts/capture-fixtures.sh` against a real workspace and committing the
output.

## Layout

```
spec/fixtures/
  sarif/                # SARIF 2.1.0 outputs
    semgrep.sarif       # 15 results, 2 unique rules, level in rule.defaultConfiguration
    eslint.sarif        # 5 results, mixed error/warning, native via @microsoft/eslint-formatter-sarif
    eslint-empty.sarif  # 0 results edge case (clean codebase)
    ruff.sarif          # 6 results, all level=error, native --output-format sarif
    ruff-empty.sarif    # 0 results edge case
    osv-scanner.sarif   # 1 result, level=warning, severity in rule, real CVE
    gitleaks.sarif      # 1 result (placeholder key), level=null, native
    checkov.sarif       # 1 result, level=error, IaC native
  sbom/
    osv-scanner.cdx.json  # 1 component, 1 vulnerability, CycloneDX 1.5, ratings include CVSSv4
  raw/                  # Raw tool outputs (input for jq converters in lib/transverse/sarif.sh)
    prettier.txt        # prettier --check stderr, 1 file flagged
    tsc.txt             # tsc --noEmit error stream, 2 errors (TS2322 + TS2304)
    gitleaks.json       # gitleaks --report-format json (gitleaks >= 8.30 also supports SARIF natively)
    dotnet-format.json  # dotnet format whitespace --report, 1 file with 17 WHITESPACE changes
```

## Per-fixture provenance

| Fixture | Source command | Tool version | Workspace |
|---|---|---|---|
| `sarif/semgrep.sarif` | `semgrep scan --config=auto --sarif` (trimmed via jq to keep only rules referenced by results) | semgrep 1.157.0 (analysis runner) | brik/ repo (bash codebase) |
| `sarif/eslint.sarif` | `eslint . --format @microsoft/eslint-formatter-sarif` | eslint 9.x with @microsoft/eslint-formatter-sarif | synthetic-but-real dirty JS file with no-unused-vars + eqeqeq + no-undef violations |
| `sarif/eslint-empty.sarif` | same | same | briklab test-projects/node-complete (clean) |
| `sarif/ruff.sarif` | `ruff check . --output-format sarif --select E,F,W,I` | ruff (latest pip) | synthetic-but-real dirty Python file with unused imports + multiple imports |
| `sarif/ruff-empty.sarif` | same | same | briklab test-projects/python-complete (clean) |
| `sarif/osv-scanner.sarif` | `osv-scanner scan source --format sarif` | osv-scanner 2.3.5 (scanner runner) | briklab test-projects/node-complete package-lock.json (real GHSA-w5hq-g745-h8pq on uuid 8.3.2) |
| `sarif/gitleaks.sarif` | `gitleaks dir <path> --report-format sarif` (trimmed) | gitleaks 8.30.1 (scanner runner) | brik/ repo, finds FAKEKEYDATA placeholder in spec/transverse/ssh_spec.sh |
| `sarif/checkov.sarif` | `checkov -d <path> --framework dockerfile -o sarif` | checkov 3.2.517 (analysis runner) | briklab test-projects/node-complete/Dockerfile |
| `sbom/osv-scanner.cdx.json` | `osv-scanner scan source --format cyclonedx-1-5` | osv-scanner 2.3.5 | same as osv-scanner.sarif |
| `raw/prettier.txt` | `prettier --check <file>` | prettier 3.8.3 | synthetic-but-real malformed JS |
| `raw/tsc.txt` | `tsc --noEmit` | typescript 6.0.3 | synthetic-but-real malformed TS |
| `raw/gitleaks.json` | `gitleaks dir <path> --report-format json` | gitleaks 8.30.1 | brik/ repo |
| `raw/dotnet-format.json` | `dotnet format whitespace --verify-no-changes --report <dir>` | .NET SDK 9.0 | synthetic-but-real malformed C# Program.cs (17 whitespace diagnostics on 1 file) |

Capture date: 2026-05-04. All SARIF fixtures pass `jv schemas/external/sarif-2.1.0.json`.
The CycloneDX fixture passes `jv schemas/external/cyclonedx-1.5.schema.json`.

## Severity placement matrix (drives `_sarif._normalize_severity`)

Different SARIF producers store severity in different places. `lib/transverse/sarif.sh` must handle every case below.

| Tool | `result.level` | Lookup path | Notes |
|---|---|---|---|
| eslint | yes (`error`/`warning`) | direct | trivial |
| ruff | yes (`error`) | direct | always `error` regardless of rule type |
| osv-scanner | yes (`warning`) | direct | numeric CVSS in `properties.severity` of rule |
| checkov | yes (`error`) | direct | binary fail/pass |
| semgrep | **null** in result | `tool.driver.rules[ruleIndex].defaultConfiguration.level` | resolution by ruleId or ruleIndex; CWE in `rules[].properties.tags` as `"CWE-NN: ..."` strings |
| gitleaks | **null** in result | rules table (level inherited) | secret category derives from ruleId |

## Re-capture

```bash
brik/scripts/capture-fixtures.sh
```

The script is idempotent: it overwrites the existing fixtures with freshly-captured outputs from the runner images and briklab test-projects. Use it when:

- a tool version is bumped in `brik-images/versions.json` (verify the SARIF shape didn't drift)
- a new tool is added to the runner images
- a fixture becomes stale (e.g., new osv-scanner database releases new CVEs)

## External schemas

The official schemas used by `jv` for fixture validation live at
`brik/schemas/external/`:

- `sarif-2.1.0.json` (OASIS sarif-spec/main, 2026-05-04)
- `cyclonedx-1.5.schema.json` (cyclonedx.org/schema, 2026-05-04)
- `SCHEMAS.sha256` (provenance)
