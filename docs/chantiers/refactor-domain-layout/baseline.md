# Baseline Phase 0 - Refactor Domain Layout

**Date:** 2026-04-19
**Branch:** `refactor/domain-layout`
**HEAD:** `2cd57e1` (ci: update shellmetrics badges [skip ci])
**Checkpoint:** `baseline-phase-0`

Reference captured before any refactoring modification. Any deviation during Phase 1-6 must be explained in the roadmap journal.

---

## Test suite (ShellSpec)

| Metric | Value |
| --- | --- |
| Examples | **2036** |
| Failures | **0** |
| Duration | 138.78 s (user 122.41 s, sys 115.91 s) |
| Runtime | /opt/homebrew/bin/bash (bash 5.3.9) |
| Jobs | 16 |
| ShellSpec version | 0.28.1 |

Target Phase 6: >= 2000 examples, 0 failures.

---

## Lint (ShellCheck)

| Metric | Value |
| --- | --- |
| Scope | `runtime/bash/lib/**/*.sh` + `shared-libs/{common,gitlab,jenkins,local}/scripts/*.sh` |
| Severity filter | `-S warning` |
| Issues (W+E) | **0** |
| ShellCheck version | 0.11.0 |

Target Phase 6: 0 warnings/errors at the same severity.

---

## Coverage (kcov)

| Metric | Value |
| --- | --- |
| Aggregate | **91.64 %** |
| Lines covered | 5339 / 5826 |
| Files instrumented | 92 |
| kcov version | 43 |
| Report | `coverage/index.html`, `coverage/coverage.json` |

Target Phase 6: >= 90 % (no regression).

---

## Source code counts

| Area | Count |
| --- | --- |
| Source files (`runtime/bash/lib/**/*.sh`) | 87 |
| Spec files (`runtime/bash/spec/**/*_spec.sh`) | 122 |

Final target after refactoring (final-plan §9, files-catalog récap):
- Source files: ~70 (redistributed across 8 domain directories)
- Spec files: parity or +, mirror domain tree

---

## Tool versions

| Tool | Version |
| --- | --- |
| bash | 5.3.9 (Homebrew) |
| ShellSpec | 0.28.1 |
| ShellCheck | 0.11.0 |
| kcov | 43 |

---

## Artifacts captured

- `coverage/coverage.json` (per-file breakdown, 92 entries)
- `coverage/index.html` (HTML report)
- `coverage/sonarqube.xml`, `coverage/cobertura.xml` (CI exports)
- `/tmp/shellcheck-baseline.log` (empty - no issues)

---

## How to reproduce

```bash
cd brik/
shellspec
shellcheck -S warning runtime/bash/lib/**/*.sh shared-libs/common/scripts/*.sh \
  shared-libs/gitlab/scripts/*.sh shared-libs/jenkins/scripts/*.sh \
  shared-libs/local/scripts/*.sh
jq '{total_files: (.files | length),
     aggregate_covered: ([.files[].covered_lines | tonumber] | add),
     aggregate_total: ([.files[].total_lines | tonumber] | add)}
    | . + {percent: ((.aggregate_covered / .aggregate_total) * 10000 | round / 100)}' \
  coverage/coverage.json
```

---

## Verification protocol per phase

At the end of each phase (1 to 6), re-run the three captures and compare with this baseline. Acceptable thresholds:

| Metric | Acceptable drift |
| --- | --- |
| Examples | >= 2000 (no deletion of valid tests) |
| Failures | 0 (strict) |
| ShellCheck issues | 0 (strict) |
| Coverage aggregate | >= 90 % |

Any regression must be justified in the `roadmap.md` journal before merging the phase commit.
