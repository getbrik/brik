# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.3.0]: https://github.com/getbrik/brik/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/getbrik/brik/releases/tag/v0.2.0
[0.1.0]: https://github.com/getbrik/brik/releases/tag/v0.1.0
