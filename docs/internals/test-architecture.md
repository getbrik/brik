# Test Architecture

## TL;DR

The test suite is organised along the **11 domain notions** declared in
[`layout.md`](layout.md) and the inter-notion **dependency graph** documented
there. It is layered into four typed layers, all under
`brik/spec/{contracts,unit,integration,pipeline-e2e}/`:

- **L0 Contracts** -- a notion's static I/O contract against its JSON Schema.
- **L1 Unit** -- a notion's logic in isolation, every external binary mocked.
- **L2 Notion-pair** -- one edge of the dependency graph, the target notion real.
- **L3 Pipeline-E2E** -- the whole graph on a real orchestrator (briklab).

The former transition holding pen `spec/_legacy/` has been fully migrated and
removed: every spec now lives in its typed layer, and `spec/unit/` is purely
single-notion L1.

## Layout

```
brik/spec/
  spec_helper.sh           # SHARED: exports BRIK_HOME, BRIK_BIN, BRIK_SCHEMA, FIXTURES, EXAMPLES
  support/                 # SHARED: mock_helper.sh + its spec (referenced by 84+ specs)
  fixtures/                # SHARED: SARIF/JUnit/SBOM samples
  contracts/               # L0: per-notion static I/O contracts
  unit/                    # L1: per-notion pure logic (every external binary mocked)
    <notion>/              #     one directory per notion (stacks, stages, ...)
  integration/             # L2: one directory per dependency-graph edge
    execution-env-x-stages/    # edge #1  -- --with-deploy propagation
    planning-x-stages/         # edge #10 -- plan.json drives the stage gate
    registry-x-planning/       # edge #11 -- gate.opt_in_flag consumed by planner
    stages-x-stack/            # edge #2  -- build stage -> stacks.<stack>.build
    stages-x-package-manager/  # edge #3  -- package stage -> pkg.<reg>.publish
    stages-x-deployments/      # edge #4  -- deploy stage -> deploy.<target>.run
    stages-x-transverse/       # edge #5  -- stages -> config/env/wait contract
    stages-x-execution/        # edge #6  -- stage.run instrumentation
    stack-x-package-manager/   # edge #9  -- stacks drive npm/cargo/... CLI
    deployments-x-rollout/     # edge #8  -- health gate + strategy delegation
    findings-x-verify-stages/  # edge #7  -- shared severity + fix-classification
    adapter-parity/            # cross-cutting: adapters mirror the registry/stacks
  pipeline-e2e/            # L3: full plan-driven pipeline + orchestrator scenarios
    plan_l3_local_spec.sh
```

Each `integration/<edge>/` directory carries a `fixture.yml` documenting the
fixture the family relies on (see `spec/integration/README.md`). All 11
dependency-graph edges have an L2 family. `adapter-parity/` holds cross-cutting
parity specs that are not a single edge (see its README).

`support/` and `fixtures/` stay at the root of `brik/spec/` because they are
referenced by absolute path (`$BRIK_HOME/spec/support/...`) from 84+ specs.

## Target layers

| Layer | Scope | Tools | Per-test cost | Goal |
|---|---|---|---|---|
| **L0 Contracts** | One notion's I/O | JSON Schema + ShellSpec | < 100 ms | Verify a notion respects its static I/O contract |
| **L1 Unit** | Pure logic of one notion in isolation | ShellSpec, stubs/mocks | < 1 s | Verify if/else branches of a public function |
| **L2 Notion-pair** | One edge of the dependency graph | ShellSpec + minimal fixtures | 5-20 s | Verify a notion uses another correctly |
| **L3 Pipeline-E2E** | Whole graph + CI orchestrators | briklab (GitLab/Jenkins/local) | 2-7 min | Orchestrator parity + cases L2 cannot cover |

### L1 purity criterion

An L1 spec **mocks every external binary** (`docker`, `kubectl`, `helm`,
`npm`, `cargo`, `mvn`, `grype`, `gitleaks`, ...) and runs with only the brik
prerequisites on PATH: bash + jq + yq + jv + git + ShellSpec. It must pass in
CI (ubuntu) with no stack or deploy tool installed. If a spec needs a **real**
external binary, a real external service, or a real filesystem outside `/tmp`,
it is not L1 -- it belongs to L2 or L3.

> Note: the operative reference environment is the CI runner (ubuntu + the
> prerequisites above), not a bare busybox image. A few L1 specs rely on
> GNU-coreutils behaviour (e.g. `date`) and would not pass on pure busybox;
> that is a portability detail, not an L1 violation.

## Writing a new test

- **Pure function of a notion** -> `brik/spec/unit/<notion>/<submodule>_spec.sh`,
  mocking every external binary.
- **I/O contract of a notion** -> `brik/spec/contracts/<notion>_contract_spec.sh`
  plus the schema under `brik/schemas/<notion>/v1/<output>.schema.json`.
- **Graph edge** (e.g. "the build stage dispatches to the node stack") ->
  `brik/spec/integration/<edge>/` (create the directory if it is the first
  member of the family, with a `fixture.yml`).

## Coverage

Line/branch coverage is measured by kcov and published to Codecov:

```bash
make coverage      # shellspec --kcov over bin/, lib/, shared-libs/*/scripts/
```

The per-notion **coverage floor** lives in `codecov.yml`:
`coverage.status.project` maps each notion to its `lib/<notion>/` paths. Every
notion holds at least 80% line coverage today (measured with kcov; global
~90%), so 80% is the uniform floor; registry keeps a 90% bar and planning 85%.
A PR that drops a notion below its floor fails that notion's Codecov status
check. This is the per-notion PR-gate -- there is no bespoke coverage script;
kcov + Codecov are the single source of truth.

> Caveat: kcov instruments the in-process ShellSpec bash, not child processes.
> A CLI command exercised only via `When run script "$BRIK_BIN" <cmd>` runs in
> a subprocess, so its lines read as uncovered even when the end-to-end spec
> passes. To make that coverage visible, add in-process `When call cli.<cmd>.*`
> tests -- the `*_internals_spec.sh` pattern -- alongside the end-to-end spec
> (see `registry_internals_spec.sh`). Before treating a 0% file as untested,
> check whether it is only covered by a subprocess spec.

## Running the suite

```bash
cd brik && shellspec            # everything

shellspec spec/contracts/       # L0
shellspec spec/unit/            # L1
shellspec spec/integration/     # L2
shellspec spec/pipeline-e2e/    # L3
```

## References

- [Notion layout](layout.md)
- [Stage lifecycle](stage-lifecycle.md)
