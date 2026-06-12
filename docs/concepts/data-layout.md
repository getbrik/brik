# Pipeline Data Layout

This document defines the **on-disk layout** that Brik produces at runtime,
the contract between the runtime and external consumers (CI platforms,
operators, downstream tooling), and the helpers stages should use to
write under this layout.

For the code-level domain layout (the `lib/` tree, nine notions), see
[internals/layout.md](../internals/layout.md). For the architectural
rationale behind separating code from runtime data, see
[architecture.md](architecture.md).

## Two roots, two contracts

Every Brik run materialises two top-level directories under
`${BRIK_WORKSPACE}` (the project being built):

| Root              | Contract               | Audience                                   | Lifecycle                 |
|-------------------|------------------------|--------------------------------------------|---------------------------|
| `brik-artifacts/` | Public, schema-stable  | CI platforms, downstream tools, operators  | Long retention (job artifacts) |
| `.brik-logs/`     | Best-effort, internal  | Operators (debug), forensic post-mortems   | Short retention (debug)        |

`brik-artifacts/` is the **product**: per-stage report fragments, SARIF
findings, JUnit reports, coverage reports, SBOM, aggregate report copies.
External tools may pin filenames here -- the schema is versioned
(`schema_version: "1.1"` for fragments) and additions are backward-compat.

`.brik-logs/` is the **trace**: per-stage `.log` files, the
`pipeline.env` cross-stage env file, the aggregate-report backend
(before notify copies it to `brik-artifacts/`), the policy cache,
`plan.json` (the reproducible stage-selection plan with the referential
fingerprint for audit), and mutex lock files. Format is **not contractual**
-- file names and shapes may change between Brik versions without warning.
Consumers who scrape these files do so at their own risk; the supported way
to read pipeline state is through `report.read` or the JSON in
`brik-artifacts/aggregate-report.json`.

The visibility split (`.brik-logs/` is dot-prefixed, `brik-artifacts/`
is not) reflects the contract: the visible directory is what users
inspect; the hidden directory is what they ignore unless debugging.

## Depth rule

Both roots follow the same depth rule: **max two levels**, structure
`<stage>/<file>`. Examples:

```text
brik-artifacts/sast/findings.sarif        # OK (depth 2)
brik-artifacts/sast/sast.sarif            # OK (raw tool output)
brik-artifacts/test/junit.xml             # OK
brik-artifacts/test/coverage/coverage.xml # OK -- coverage/ is a legitimate
                                          # multi-output directory (cobertura
                                          # XML + lcov + HTML report)
.brik-logs/init.log                       # OK
.brik-logs/policy.cache.json              # OK
```

The `test/coverage/` subdirectory is an exception that proves the rule:
it exists because coverage tools (nyc, coverage.py, jacoco, cargo-llvm-cov,
dotnet) emit several formats (Cobertura XML, lcov.info, HTML browser,
text-summary) and must point them all at one directory.

## SARIF naming convention

SARIF-native stages produce **two distinct files** per stage by design:

| File                            | Producer                  | Role                                 |
|---------------------------------|---------------------------|--------------------------------------|
| `<stage>/<tool-or-stage>.sarif` | The tool itself           | Raw tool output, audit-able          |
| `<stage>/findings.sarif`        | `findings.process`        | Post-policy, canonical (uniform)     |

Examples by stage:

| Stage           | Raw                                | Post-policy                          |
|-----------------|------------------------------------|--------------------------------------|
| `sast`          | `sast/sast.sarif` (semgrep)        | `sast/findings.sarif`                |
| `lint`          | `lint/<check>.sarif` (per check)   | `lint/findings.sarif`                |
| `container-scan`| `container-scan/container-scan.sarif` (grype) | `container-scan/findings.sarif`      |
| `scan`          | `scan/deps.sarif`, `scan/secret.sarif` | `scan/findings.sarif`            |
| `test`          | (synthesised directly)             | `test/findings.sarif`                |

`findings.sarif` is the **single canonical entry point** for any
consumer that wants the actionable findings of a stage with policy
filtering applied. The aggregator (`report.aggregate_fragments`)
reads this file. Operators who need the raw tool output (e.g. to
compare against post-policy filtering) can read the sibling.

For lint specifically, `<stage>/<check>.sarif` is per-check
(`lint.sarif`, `format.sarif`, `type_check.sarif`) -- multiple
sibling files, one per configured check. The post-policy
`findings.sarif` aggregates all checks.

## Path helpers

Stages MUST use the helpers in `lib/transverse/artifacts.sh`
instead of building paths inline. This keeps the convention
discoverable, lintable, and refactor-safe.

### Artifacts (public)

```bash
brik.artifacts.root                  # ${BRIK_WORKSPACE}/brik-artifacts (pure query)
brik.artifacts.dir <stage>           # ${BRIK_WORKSPACE}/brik-artifacts/<stage> (mkdir -p)
brik.artifacts.path <stage> <file>   # ${BRIK_WORKSPACE}/brik-artifacts/<stage>/<file> (mkdir -p parent)
```

### Logs (operational)

```bash
brik.logs.root                       # ${BRIK_WORKSPACE}/.brik-logs (pure query)
brik.logs.dir <stage>                # ${BRIK_WORKSPACE}/.brik-logs/<stage> (mkdir -p)
brik.logs.path <relpath>             # ${BRIK_WORKSPACE}/.brik-logs/<relpath> (mkdir -p parent)
```

### `BRIK_LOG_DIR` resolver

For modules that need the log dir directly (context.create,
pipeline.env.init, report.init), use `_brik.log_dir._resolve` from
`lib/pipeline/logging.sh`:

```bash
local log_dir
log_dir="$(_brik.log_dir._resolve)"
```

Precedence:

1. `$BRIK_LOG_DIR` (explicit override, always wins when non-empty)
2. `${BRIK_WORKSPACE}/.brik-logs` (workspace-derived; the standard)
3. `/tmp/brik/logs` (ultimate fallback for pre-init contexts where
   `BRIK_WORKSPACE` is not yet exported, e.g. Jenkins agent setup)

## CI shipping contract

Both roots ship as job artifacts on every CI platform. On GitLab,
each job's `artifacts.paths` lists `.brik-logs/` and `brik-artifacts/`,
with `artifacts.exclude: [.brik-logs/*.lock, .brik-logs/context-*]`
to drop mutex lock files and per-stage temp context files (which
should not persist beyond stage cleanup). On Jenkins, the notify
stage's `archiveArtifacts` does the same with the equivalent Ant
glob excludes.

The `init` job additionally declares
`artifacts.reports.dotenv: .brik-logs/pipeline.env` so GitLab
auto-injects the cross-stage env vars into downstream jobs.
Jenkins reads the same file via `brikReadDotenv` to resolve the
stage-specific runner image.

## See also

- [Architecture](architecture.md) -- the layered design that produces this layout
- [Pipeline context](pipeline-context.md) -- how a stage receives its execution context
- [Internals layout](../internals/layout.md) -- the source-code domain layout
