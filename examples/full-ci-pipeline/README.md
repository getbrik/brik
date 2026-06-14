# full-ci-pipeline

`node 22` · **CI** · complete reference

> [!NOTE]
> A kitchen-sink CI configuration: every quality and security control, plus
> reporting, packaging, notifications, and planner selection.

## When to use this
As a menu, not a default. Reach for it to see how a given block is written,
then copy only what your project needs.

## What it configures
- **quality** lint (eslint), format (prettier, check mode), type check (tsc),
  and `findings.policy: strict`.
- **security** every scanner -- SAST (semgrep), deps (osv-scanner + SBOM),
  secrets (gitleaks), license allow/deny, container, IaC (checkov) -- behind a
  global `severity_threshold`.
- **test** a coverage threshold plus lcov + JUnit reports.
- **package** multi-arch Docker (`platforms`), `build_args`, registry UI URL.
- **notify / hooks / git** Slack + email routing, inline stage hooks, and the
  commit identity.
- **pipeline** `selection.mode: balanced` with a per-stage impact override.

## Try it
```bash
brik validate --config examples/full-ci-pipeline/brik.yml
```

## Reference
- [`quality`](../../docs/reference/configuration/quality.md) - lint, format, type check, findings
- [`security`](../../docs/reference/configuration/security.md) - SAST, deps, secrets, license, container, IaC
- [`package`](../../docs/reference/configuration/package.md) - Docker build and push
- [`pipeline`](../../docs/reference/configuration/pipeline.md) - planner selection

> [!WARNING]
> This is a maximal reference, not a recommendation to enable everything at
> once. Most projects need only a handful of these blocks.
