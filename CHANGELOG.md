# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **GitLab pipeline.env propagation** -- declare
  `artifacts.reports.dotenv: .brik-logs/pipeline.env` on every job template
  (release, build, lint, sast, scan, test, package, container-scan, deploy,
  notify), not just init. GitLab merges dotenv files from `needs:` in
  declaration order with the last upstream winning on key collisions, so the
  cumulative state reaches every consumer. Without this, GitLab restored
  init's snapshot of `pipeline.env` in every downstream job, dropping keys
  published by later stages (most visibly `BRIK_APP_VERSION`, which made
  `package` tag images with a short SHA instead of the release version on
  tagged commits). Parity enforced by
  `spec/integration/gitlab_dotenv_parity_spec.sh`. Jenkins and local
  wrappers are unaffected -- they already source `pipeline.env` directly at
  each stage start.

## [0.5.0] - 2026-05-16

99 commits since 0.4.0. Major release built on three converging chantiers:
the unified findings management framework (DSI-owned policy contract,
built-in presets, 7 non-SARIF converters), the pipeline behavior model
(fix-exists axis, tool-blocking semantics, tool resolution,
coverage-as-finding, trigger gating), and the tech / business orthogonal
axes refactor (report schema 1.0 -> 1.1, new gatekeeper rc semantics).
HTML aggregate report v2 lands branded with per-stage telemetry,
repo deep links, and a notify dispatch panel. Legacy exit-code-99 and
`*_ENABLED` opt-outs are removed.

### Added

- **Findings management framework** (`lib/transverse/findings/`,
  `lib/transverse/findings.sh`) -- unified collect / ignore / aggregate /
  report pipeline for every stage that emits findings. SARIF 2.1.0 is the
  pivot format. Three built-in policy presets (`pragmatic` default,
  `strict`, `permissive`) cover the bulk of cases with zero project
  configuration. The findings flow runs `findings.process` per stage,
  `findings.merge_pipeline` at end-of-pipeline (writes
  `brik-artifacts/aggregate.sarif`), and feeds the L4 v2 business
  contract (`business.findings.{failing, ignored.{by_source,
  by_severity}}`).
- **DSI-owned `brik-policy.yml`** distributed via `BRIK_POLICY_URL`
  (CVE and path allowlists, mandatory `expires`, project scoping). The
  `init` stage non-blockingly surfaces "expiring soon" entries. New
  guides at `docs/operations/policy.md` and
  `docs/operations/risk-management.md` cover when to allowlist, what to
  record (`reason`, `expires`, scope), review cadence, and the
  anti-patterns the schema refuses.
- **Non-SARIF converters + dispatcher** (`lib/transverse/findings/
  converters/`) -- 7 tool converters: junit, ruff, bandit, dockle,
  trufflehog, scancode, clippy. New entries register through the
  dispatcher so adding an N+1 tool is one converter file.
- **GitLab non-Ultimate exporter** -- aggregate SARIF projected to
  `gl-sast-report.json` for the standard Security tab. Four new
  sections in `aggregate-report.md` (Active policy / Failing / Ignored /
  Expiring soon). Warnings NG aggregate tool entry for Jenkins.
- **Fix-exists annotation** (`lib/transverse/fix_classifier.sh`) --
  every SARIF result gets a `brikFixClassification` property
  (`has_fix | no_fix | unknown`) before policy application. Per-stage
  heuristics cover container-scan (grype `fixState`), sast (semgrep
  `Fix Version`), scan-deps (`fixes[]`), secret / lint / format / test
  (always `has_fix`).
- **Tool-blocking annotation** -- lint and format SARIFs gain a
  `brikToolBlocking` property based on the SARIF tool driver name + the
  per-result severity input (eslint `error` -> true, `warn` -> false;
  ruff `E*/F*` -> true, `I*/W*` -> false; checkstyle / dotnet-format
  `error` -> true). `findings.aggregate` filters `failing.has_fix` and
  `failing.no_fix` to the tool-blocking subset only.
- **Severity normalization** (`lib/transverse/severity.sh`) -- pure
  mapping from tool-native severity (eslint, ruff, checkstyle,
  dotnet-format, semgrep, grype, osv-scanner, gitleaks) onto the
  canonical 5-bucket scale `{critical, high, medium, low, info}`.
- **Tool resolution** (`lib/transverse/tool_resolver.sh`) --
  `tool_resolver.resolve <tool>` walks workspace `node_modules/.bin/`,
  then `$PATH`, then `<BRIK_HOME>/tools/`, emitting a
  `{path, version, provenance}` JSON descriptor. Missing tools become
  typed findings instead of generic stage failures.
- **Coverage SARIF emission** (`lib/transverse/coverage.sh`) -- the
  existing `brik.coverage.gate` legacy hard-fail is now paired with
  `brik.coverage.emit_sarif` which produces a SARIF result (rule
  `brik-coverage-below-threshold`, `level=error`) when measured
  coverage falls below `test.coverage.threshold`. The finding flows
  through `findings.process` so it is classified, policy-checked, and
  surfaced via `business.findings.failing`. LCOV (`lcov.info`) parsing
  added alongside Cobertura and Jacoco, completing coverage for the
  five canonical stack toolchains.
- **Trigger gating** (`lib/transverse/gating.sh`) -- new
  `release.trigger`, `package.trigger`, `deploy.trigger` blocks in
  `brik.yml` decouple the on-tag / on-main / on-feature / manual
  behaviours. `gating.should_run_stage <PREFIX>` answers whether the
  current pipeline context satisfies any of the configured flags.
  When the block is absent, the stage runs as before (legacy compat
  preserved by the `BRIK_<PREFIX>_TRIGGER_CONFIGURED` sentinel).
- **Business outcome filter** (`lib/pipeline/business.sh`) -- pure
  function `business.evaluate` computes the typed business outcome
  (`status: success | warning | error`, `reason`) from the matrix
  `(tech.status, side-band findings.ignored, pipeline.context,
  tech.kind, fix-exists axis)`. The 10-row matrix consumes the
  fix-exists axis and yields typed reasons
  (`"<kind> (fix available, not applied)"` etc.) so aggregate-report
  rows are self-documenting. Wired into `_stage._finalize_fragment`
  so every stage fragment now carries `business.{status, reason}`.
- **Pipeline context** -- `BRIK_COMMIT_TAG` resolves to
  `pipeline.context = release` (non-empty) or `snapshot` (empty).
  Drives the `continue_on_error` default (snapshot lenient, release
  strict) and the business filter severity. Override via the new
  `BRIK_CONTINUE_ON_ERROR=0|1` environment variable; the legacy
  `--continue-on-error` CLI flag still works.
- **Pipeline gatekeeper** -- `pipeline.run` aggregates per-stage
  `business.status` into `summary.business.{success_count,
  warning_count, error_count}` and `pipeline.business.status`
  (worst-of). The pipeline return code is now derived from
  `pipeline.business.status`: `error` => `BRIK_EXIT_FAILURE`,
  anything else => `0`. `stages.notify` gates the same way at the end
  of CI runs.
- **Branded HTML aggregate report v2** (`lib/pipeline/_branding.sh`)
  -- the HTML aggregate report carries the Brik logo (base64-embedded,
  128x128) and a link to the project. CSS, JS, and the logo are
  inlined so the report stays browseable straight from a CI artifact
  with no external fetches. New section + tile rendering pattern
  unifies the per-stage layout.
- **Repository deep links** -- `pipeline.commit.repo_url` is detected
  by init from `CI_PROJECT_URL` / `GIT_URL` / `git remote` and
  normalised to a credential-free HTTPS form (SSH forms converted,
  `.git` suffix dropped). The HTML renderer turns it into deep links
  to commits, branches, and tags on the hosting forge (GitLab,
  GitHub, Gitea, Bitbucket).
- **Notify dispatch panel** -- `pipeline.notify` (per-channel
  configuration intent + gatekeeper decision) is injected into the
  aggregate by `stages.notify` after aggregation, and the HTML view
  is re-rendered so the archived report surfaces which channels would
  fire and the final pass / fail decision.
- **`init.tech.tool_versions`** -- the semver of each prerequisite
  tool (`yq`, `jq`, `jv`) present on the runner, surfaced in the init
  panel; a tool absent from the runner is omitted so consumers can
  tell "missing" from "present, version unknown".
- **`build.business.artifact.main_file`** -- the build artifact probe
  is now stack-aware (per-stack candidate directory order, empty
  candidates skipped) and records the representative shipped file
  (`*.jar`, `*.whl`, `*.tgz`, `*.nupkg`, rust binary, ...). When set,
  `size_bytes` and `sha256` describe that file rather than the
  directory total.
- **`package.business.registry.ui_url`** -- a browseable registry UI
  URL, distinct from the docker push endpoint (Nexus 3 splits these
  on ports 8081 vs 8082), sourced from
  `BRIK_PACKAGE_REGISTRY_UI_URL` or the new `package.registry.ui_url`
  block in `brik.yml`. The HTML report links to the image page.
- **`BRIK_DRY_RUN` first-class flag** -- exposed as a CLI flag
  (`brik run pipeline --dry-run`) and as a CI UI input on GitLab and
  Jenkins. Every level of the pipeline report carries a `dry_run`
  field for downstream consumers.
- **Two-root data layout** -- pipeline state is split between
  `brik-artifacts/` (shippable outputs) and `.brik-logs/`
  (intra-pipeline state, including the unified
  `.brik-logs/pipeline.env` that replaces the legacy
  `brik-init.env`). New `logs.path` helpers derive paths from
  `BRIK_WORKSPACE`. GitLab passes `.brik-logs/pipeline.env` between
  all jobs as a dotenv artifact.
- **Stage UX polish** -- redesigned stage banner with metadata + box
  drawing, ANSI color support with a new `log.success` level, and a
  Unicode notify recap table printed at end of pipeline alongside the
  existing `Status` column with a new `Business` column.
- **Schema v1.1 typed counters** --
  `stages[].business.findings.failing` migrates from scalar int to
  `{total, has_fix, no_fix}` object, strictly typed with
  `additionalProperties: false`. Readers (`findings.gate`,
  `lib/pipeline/report.sh`, `lib/stages/notify.sh`,
  `_stage._record_business`) use a `(objects | .total) // (numbers)
  // 0` fallback chain to accept both shapes during the transition.
- **Fragment uniformity** -- `stage.cleanup` now unconditionally
  removes the per-stage `context-<stage>-XXXXXX` scratch file after
  `summary.build` consumes it. The `<stage>-summary.json` /
  `brik-artifacts/<stage>/<stage>.json` fragment is the sole source of
  truth for downstream consumers (E2E harness, CI artifact
  aggregators).

### Changed

- **Documentation tree restructured** into a hybrid user-journey
  layout under `docs/` (`concepts/`, `configuration/`,
  `getting-started/`, `internals/`, `operations/`, `platforms/`).
  `docs/concepts/architecture.md` "Decision matrix" rebuilt around
  the 10-row fix-exists matrix that mirrors `lib/pipeline/business.sh`,
  plus a "Supporting modules" table enumerating fix_classifier,
  severity, tool_resolver, coverage, gating.
- `docs/internals/` gains pages for tool-native severity, tool-blocking
  annotation pipeline, tool resolver, `release.trigger` /
  `package.trigger` / `deploy.trigger` blocks, and the updated
  `test.coverage.threshold` semantic (SARIF flow).
- Report schema v1.1 gains `pipeline.commit.repo_url` and
  `pipeline.notify` (both optional, additive on top of the 1.0 -> 1.1
  bump).
- Config schema gains the `package.registry` block (`ui_url`).
- `aggregate-report.md` carries a "Business outcome" section
  (status + per-bucket counts); `aggregate-report.html` adds a
  "Business outcome" kvCard.
- Snapshot context is preserved on Jenkins branch builds whose HEAD
  also carries a tag (no accidental release classification).
- `BRIK_COMMIT_SHORT_SHA` width aligned at 7 chars across GitLab and
  Jenkins.
- `python` stack uses per-stage `PYTHONUSERBASE` to avoid pip install
  races on parallel verify lanes.
- Stack builds pin `SOURCE_DATE_EPOCH` for reproducible Python wheels.

### Changed (BREAKING)

- **Report schema bumped to 1.1.** Producers now emit
  `schema_version: "1.1"` on both fragments (`report.write_fragment`)
  and the aggregate (`report.aggregate_fragments`). The aggregator's
  input filter accepts both `1.0` and `1.1` so archived fragments and
  external producers can keep aggregating cleanly while they migrate.

  Migration for external consumers (dashboards, exporters):
  1. **Loose validators** (consume the JSON, accept extra fields):
     no change required. The shape is additive.
  2. **Strict validators** (validate against the published schema):
     point at `schemas/report/v1.1/{fragment,aggregate}.schema.json`
     instead of `v1`. The `v1` schema stays available for reading
     historical artefacts only.
  3. **Field consumers**: the legacy `tech.warning`,
     `tech.warning_reason`, and `summary.warnings` are gone. The
     equivalent signal lives in per-stage `business.{status, reason}`
     and aggregate `summary.business`.
- **`pipeline.run` rc semantics**. A failing stage in `snapshot`
  context now resolves to `business.warning` and the pipeline returns
  `0` instead of `1`. Release context (with `BRIK_COMMIT_TAG` set)
  keeps fail-fast and returns `1`. CI users that need the previous
  fail-fast-on-snapshot behaviour pass `BRIK_CONTINUE_ON_ERROR=0`.
- **Wrapper UI**. GitLab no longer paints a "yellow warning" job for
  the legacy code 99 path (`allow_failure: { exit_codes: [99] }`
  removed from lint / sast / scan / container-scan templates).
  Jenkins no longer marks the stage `UNSTABLE` on rc=99. A real
  stage failure still paints red as before; a `business.warning`
  (e.g. findings ignored by policy) is reported via
  `aggregate-report.{md,json,html}` only.
- **Release version source.** `release.compute_version` now prefers
  `BRIK_TAG` over `git describe` when both are present, mirroring
  Jenkins tag-trigger semantics.

### Removed

- Legacy `BRIK_*_ENABLED` dotenv exports for `lint`, `format`, `sast`,
  `scan`, `secret`, `container-scan`, `test` -- the shift-left contract
  means these stages always run; explicit opt-outs go through the
  trigger block (release / package / deploy) or the policy preset
  (findings stages). `quality.lint.enabled` in `brik.yml` is still
  accepted by the schema but no longer honoured at runtime; the
  legacy key is documented as deprecated and triggers a deprecation
  warning at init time.
- `BRIK_EXIT_SKIP_WITH_WARNING` (exit code 99) from
  `lib/pipeline/error.sh`.
- `stage.skip_with_warning` helper from `lib/pipeline/stage.sh`.
- `summary.warnings` aggregation from `report.aggregate_fragments`.
- The `*.enabled=false` opt-out for
  `lint / sast / scan / container_scan` in `brik.yml`.
- `E2E_OPTIONAL_JOBS` convention from the briklab E2E harness.

### Fixed

- `release` stage prefers `BRIK_TAG` over `git describe` when
  computing the version.
- Jenkins archives `brik-artifacts/` even when notify gates the
  build as failure.
- `pipeline.run` surfaces fragment write errors instead of swallowing
  them.
- `findings.aggregate` resolves severity and fix-state from SARIF
  rule metadata (not just per-result fields).
- `container-scan` aligns its findings stage key with the canonical
  kebab-case name.
- `sast` excludes `.brik-stage/` and (separately) workspace pollution
  from semgrep scan scope.
- `verify` skips `format` and `lint` cleanly when their tool config
  is absent.
- Repository URLs in `init.tech.report_url` / `repo_url` no longer
  leak embedded credentials from `git remote`.
- Jenkins mounts the DSI policy file into nested stage containers
  and rescues root-owned residue across stages.

### Migration from 0.4.x

Four checkpoints to verify when upgrading from a 0.4.x install:

1. **Drop `*.enabled=false` from your `brik.yml`** -- the runtime no
   longer reads `quality.lint.enabled`, `security.sast.enabled`,
   `security.scan.enabled`, or `security.container_scan.enabled`. The
   stage runs unconditionally; if you want a stage to skip, do it via
   project shape (no lint config => auto-skip with
   `tech.kind=not-applicable`). The `init` stage logs a deprecation
   warning when it sees one of the legacy keys, so you can spot
   leftovers in the CI output.
2. **Stop expecting exit code 99** -- `BRIK_EXIT_SKIP_WITH_WARNING`
   is gone. Wrappers (GitLab `allow_failure: { exit_codes: [99] }`,
   Jenkins `unstable()` on rc=99) no longer translate it. CI lanes
   that used `if [ $rc -eq 99 ]` must switch to reading
   `aggregate-report.json`'s `pipeline.business.status`
   (`success | warning | error`) or `summary.business.warning_count`.
3. **Update strict schema validators to v1.1** -- producers now emit
   `schema_version: "1.1"`. Loose validators that accept extra
   fields stay compatible (the shape is additive). Strict validators
   must point at `schemas/report/v1.1/{fragment,aggregate}.schema.json`.
   The aggregator still accepts `1.0` fragments on input for the
   transition window, so archived fragments remain readable.
4. **Adjust to the new snapshot rc semantics** -- a failing stage on
   a feature branch (no git tag) no longer fails the pipeline:
   `business.warning` -> rc=0. Release runs (with a git tag) keep the
   old fail-fast behaviour: `business.error` -> rc=1. CI lanes that
   need fail-fast on snapshot lanes pass `BRIK_CONTINUE_ON_ERROR=0`.

See [docs/concepts/architecture.md](docs/concepts/architecture.md) and
[docs/operations/policy.md](docs/operations/policy.md) for the model
behind these changes.

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
