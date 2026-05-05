# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-05-05

Release focused on the unified `brik-artifacts/<stage>/` layout, L4 business
aggregation across all verify stages (SARIF + CycloneDX + JUnit), a richer
`pipeline-report.json` with per-stage fragments aggregated in CI, cross-platform
gate alignment with skip-with-warning semantics, and tighter GitLab + Jenkins
shared-library integration (Warnings NG, Ultimate-only SARIF overlay).

113 commits since 0.3.0.

### Added

- **Unified `brik-artifacts/<stage>/` layout** -- every stage now writes its
  reports under a single root resolved through the new `brik.artifacts` helper
  (`lib/transverse/artifacts.sh`). Verify SARIF/SBOM defaults, test coverage and
  JUnit defaults, package/container-scan/deploy outputs all live under
  `brik-artifacts/<stage>/`. GitLab and Jenkins templates publish this root
  uniformly.
- **L4 business aggregation** -- the verify stages now feed structured findings
  into `pipeline-report.json`:
  - `lint` records `business.violations` from per-check SARIF outputs.
  - `sast` records `business.findings` from `target/sast.sarif` (SARIF 2.1.0).
  - `scan` records `business.deps`, `business.secret`, and a rollup from
    osv-scanner SARIF/CycloneDX and gitleaks SARIF.
  - `test` records `business.tests` counts from JUnit XML and branch coverage
    alongside line coverage.
  - `package` and `container-scan` record digest, registry, and durations.
  - `deploy` records `business.environments[]` with name/target/namespace/strategy.
- **SARIF + CycloneDX emission**:
  - `verify.scan.sast` emits SARIF 2.1.0.
  - `verify.scan.secret` emits gitleaks SARIF.
  - `verify.scan.deps` emits osv-scanner SARIF and a CycloneDX SBOM, with empty
    stubs when no package sources are found.
- **Pipeline-report fragments + CI aggregator** -- each stage emits a fragment;
  the CI mode aggregates them into a single `aggregate-report` consumed by
  `notify`. v1 JSON Schemas published for both fragment and aggregate.
- **Transverse helpers** -- new modules under `lib/transverse/`:
  - `sarif` parser (severity counts, CWE extraction) plus converters for
    `tsc`, `prettier`, and `dotnet format`.
  - `sbom` helpers for CycloneDX 1.5 validation and merge.
  - `junit.parse` for JUnit XML.
  - `artifact.summarize` and the `brik.artifacts` path resolver.
- **Skip-with-warning** semantics across `lint`, `sast`, `scan`, and
  `container-scan` -- the new `stage.skip_with_warning` helper records a warning
  in `summary.warnings`. Jenkins maps exit code 99 to `unstable()`; GitLab uses
  `allow_failure` so the pipeline keeps moving.
- **Schema-driven validation** -- `init` validates `brik.yml` against the JSON
  Schema, the `validate` command is now a thin wrapper, and `doctor` prefers
  `jv` for validation. New `config.validate_schema` toggle.
- **Test framework unification** -- vitest support for Node and unified dotnet
  test framework selection. Coverage threshold is now enforced after the Test
  stage.
- **Deploy enhancements** -- `auth_token_var` for the ArgoCD controller,
  `git_token_var` for the GitOps target, schema support for
  `deploy.environments[].source`, and routing through `rollout.strategy` when
  configured.
- **Auto-generated config reference** -- `scripts/gen-config-reference.sh`
  produces per-section markdown tables from the JSON Schema; a `validate-docs`
  target gates drift in CI.
- **Per-stack configuration guides** for node, python, java, rust, and dotnet
  (under `docs/`).

### Changed

- **Jenkins shared library**:
  - SARIF surfaced in the Warnings NG dashboard via `recordIssues`.
  - `init` and `notify` now run in `brik-runner-base` (the `useDocker` fallback
    is gone).
  - `triggered_by` populated from Jenkins build causes; per-stage fragments are
    stashed/unstashed for `notify`.
  - Runner container memory cap raised from 2g to 4g.
  - Internal cleanup: `resolveHome` and `dockerArgs` extracted into vars.
- **GitLab shared library**:
  - SARIF reports split into an Ultimate-only conditional overlay
    (Free/Premium pipelines no longer fail on the unsupported `sast` artifact
    contract).
  - `brik-build` chained after `brik-release`; every stage publishes
    `brik-artifacts/`; `notify` chained via `needs`.
- **Pipeline metadata** -- CI metadata is normalized and surfaced in the
  aggregate; stage durations are recorded in millisecond precision.
- **Schema** -- declared defaults moved into structured `default` keys; unused
  `test.commands.{unit,integration,e2e}` dropped; `report` enrichment for
  `init.commit` and `release.changelog` audit metadata.

### Fixed

- **`verify.format`** writes `.prettierignore` inside the workspace argument
  (not the shell `cwd`), excludes `.cache`, and extends the ignore list to
  cover `target/` and `brik-artifacts/`. The shared-workspace pollution that
  previously surfaced as spurious prettier failures is gone.
- **`verify.scan.deps`** writes empty SARIF and CycloneDX stubs when no package
  sources are found, so downstream consumers (Warnings NG, Ultimate overlay)
  always receive valid input.
- **`package`** preserves the registry port and the source digest from
  `RepoDigests`, so the digest recorded in the report matches the pushed image.
- **`container-scan`** reads the package fragment directly so cross-platform
  parity is preserved between GitLab and Jenkins.
- **`report`** records the actual stage execution image (not the project
  default), serializes concurrent fragment writes, and recovers the git tag on
  Jenkins.
- **Schema** -- `hooks` values are typed as strings (not arrays).

### Documentation

- New brik-artifacts/<stage>/ layout documentation.
- Pipeline-report fragment / aggregate flow documented in `architecture.md`,
  including a Platform Stage Mapping section.
- Per-stage `pipeline-report.json` field shape documented in `reference.md`.
- Per-section config reference auto-generated from the schema (build, deploy,
  git, hooks, notify, package, publish, quality, security).
- Per-stack configuration guides for node/python/java/rust/dotnet.
- Credential indirection clarified, GitOps repo URL contract fixed.
- Pipeline Flow representation aligned across `README.md` and overview docs.

### Validation

End-to-end runs and unit suites green on the `*-complete` test fixtures
(briklab Jenkins + GitLab) and the local `shellspec` suite.

## [0.3.0] - 2026-04-27

Major release: domain-layout refactor of `lib/`, multi-stage reliability and
security improvements across the pipeline, opt-in test reports contract,
and automatic GitLab coverage badge.

163 commits since 0.2.0.

### Added

- **Test reports opt-in contract** -- new `quality.test.reports.{enabled,coverage,junit}` field in `brik.yml`. When enabled, brik injects per-stack reporter flags so the test stage produces real JUnit + coverage artifacts:
  - node (jest): `jest-junit` + jest cobertura reporter, post-test rename to `coverage/coverage.xml`
  - python (pytest): `pytest --junitxml` + `pytest-cov` cobertura
  - java (maven surefire): surefire XMLs flattened to `reports/junit/`, plus jacoco coverage when the plugin is configured
  - rust (cargo nextest): nextest.toml ci profile + `cargo-llvm-cov --cobertura`
  - dotnet (XPlat Code Coverage): JunitXml.TestLogger + post-test flatten of `coverage.cobertura.xml` to a stable path
- **Automatic GitLab coverage badge** -- the test stage emits a canonical `[brik] coverage: XX.XX%` line that the GitLab template parses with a generic regex. Works for every stack out of the box; no per-project configuration needed. New helper `lib/transverse/coverage.sh` reads cobertura `line-rate` or jacoco `<counter type="LINE"/>` aggregates.
- **`pipeline-report.json`** -- per-stage status with tech/business split, recorded centrally via `report.record`. Rendered to a Markdown summary by the notify stage and archived as a CI artifact.
- **Domain-layout structure for `lib/`** -- code organised by domain: `pipeline/`, `cli/`, `stages/`, `stacks/`, `transverse/`, `deployments/`, `rollout/`, `package-managers/`. Specs follow the same structure.
- **Native Cargo publish** with Nexus sparse protocol.
- **Lint statuses** -- the report distinguishes `disabled / not-applicable / skipped / passed / failed`.
- **Tool version monitoring** -- "new version available" entries land in `pipeline-report.json` instead of being lost in CI logs.

### Changed

- **`bin/brik`** reduced to a thin dispatcher (~190 lines) delegating every subcommand to `lib/cli/<command>.sh`.
- **`stages.init` is the single source of truth for `brik.yml`** -- downstream stages read from the dotenv it produces; no other code parses the project config.
- **Docker stack** migrated to `docker buildx build` (with legacy fallback when buildx is unavailable). Removes the deprecation warning and produces a canonical digest for the upcoming promotion model.
- **GitLab `coverage_format`** is hardcoded to `cobertura` in the template (only `cobertura` and `jacoco` are accepted by GitLab; the value is validated at YAML parse time, before any dotenv variable resolves). Java users override `coverage_report` at the project level.
- **Lint contract** -- ESLint 10 flat config support, Tier 2 strict (refuses `.eslintrc.*` when eslint >= 9), `_deps.sh` propagates exit codes (no more masking via `|| true`).
- **Jenkins pipeline** wraps each stage in try/catch so the stage view shows every stage even when an early `sh` fails.
- **Container scan** lifted to its own stage with a delegation contract.

### Fixed

- **Release stage** -- propagates real exit codes; resolves git identity from `brik.yml` (`git.user.{email,name}`) or CI vars; `git.tag` is idempotent on the same SHA; no-op `prepare` when the tag is already at HEAD.
- **`brik-init` artefacts** -- `.brik-logs/pipeline.env` is archived as a GitLab artifact so per-stage Docker containers can reload the dotenv even when `/tmp` is ephemeral per stage. Jenkins persists `BRIK_LOG_DIR` under `WORKSPACE` for the same reason.
- **`pipeline.env` quoting** -- multi-line values now go through `printf %q` so they round-trip through `source` cleanly (no more orphan tokens treated as shell commands).
- **`_deps` skip logic** detects stale `node_modules` against the current `package-lock.json` (Jenkins workspace caching no longer masks devDependency changes). Skips silently when npm or pip is missing from the runner.
- **SAST** blocks on findings via `--error` and a configurable severity threshold.
- **`osv-scanner`** is actionable -- warns on missing lockfile, exposes its full output, tolerates transient extraction errors.
- **`gitleaks`** runs with `--platform "${BRIK_PLATFORM}"` (override via `BRIK_GITLEAKS_PLATFORM`).
- **`stages.notify`** copies the pipeline report to the workspace and warns on `cp` failures (no more silent loss).
- **Deploy SSH** -- `rsync` no longer ships the CI-state directories (`.brik-logs/`, etc.) to remote hosts.
- **Examples** -- `minimal-node` package.json + src + test fixture restored.
- **Cargo publish** allows a dirty workspace.

### Breaking changes

- **`build.<stack>_version` is rejected.** The schema declares `additionalProperties: false` on the `build` block. Move `build.java_version` / `build.node_version` etc. to `project.stack_version`.
- **`publish.docker.image` is deprecated** in favour of `package.docker.image` (single source of truth).
- **`quality.test.reports.coverage.format: lcov`** is not surfaced in the GitLab template. The template hardcodes `cobertura`. Java users override `coverage_report` at the project level (see `shared-libs/gitlab/README.md`).
- The `--severity` flag was dropped from the osv-scanner invocation (incompatible with osv-scanner v1; severity continues to be enforced via brik configuration but is no longer passed to the binary).

### Documentation

- AI-assisted development transparency notice in the README.
- New credentials guide for configuring secrets.
- Architecture, layout, and reference docs realigned with the domain-layout structure.
- README "Test reports" subsection documenting the opt-in + auto coverage badge.
- README example brik.yml cleaned: removed the rejected `build.java_version` and the redundant `command: mvn package -DskipTests`.
- Pre-refactor baseline metrics snapshot for audit.

### Validation

End-to-end validated on the briklab lab against the `*-complete` test
fixtures:

- `briklab.sh test --jenkins --complete` : **5/5 PASS** (node, python, java, rust, dotnet)
- `briklab.sh test --gitlab --complete`  : **5/5 PASS**

[0.4.0]: https://github.com/getbrik/brik/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/getbrik/brik/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/getbrik/brik/releases/tag/v0.2.0
[0.1.0]: https://github.com/getbrik/brik/releases/tag/v0.1.0
