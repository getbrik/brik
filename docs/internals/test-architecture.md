# Test Architecture

## TL;DR

The test suite is organised along the **11 domain notions** declared in
[`layout.md`](layout.md) and the inter-notion **dependency graph** documented
there. The architecture is layered:

- Pre-existing tests live under `brik/spec/_legacy/` and continue to run
  during the transition.
- The new four-layer architecture (L0 Contracts / L1 Unit / L2 Notion-pair
  / L3 Pipeline-E2E) is built **alongside** under
  `brik/spec/{contracts,unit,integration,pipeline-e2e}/`.
- `_legacy/` shrinks as specs migrate into the typed layers and is
  scheduled for removal once coverage parity is reached.

## Layout

```
brik/spec/
  spec_helper.sh           # SHARED: exports BRIK_HOME, BRIK_BIN, BRIK_SCHEMA, FIXTURES, EXAMPLES
  support/                 # SHARED: mock_helper.sh + its spec (referenced by 84+ specs)
  fixtures/                # SHARED: SARIF/JUnit/SBOM samples
  _legacy/                 # TRANSITION: ~206 pre-existing specs, organised by notion
    cli/
    deployments/
    integration/
    package-managers/
    pipeline/
    planning/
    registry/
    rollout/
    schemas/
    stacks/
    stages/
    transverse/
  contracts/               # L0: per-notion static I/O contracts
  unit/                    # L1: per-notion pure logic (in progress)
  integration/             # L2: per-edge tests (S3 -- all 11 graph edges landed)
    execution-env-x-stages/    # edge #1  -- D1 --with-deploy propagation
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
  pipeline-e2e/            # L3: 3-5 orchestrator scenarios (in progress)
```

Each `integration/<edge>/` directory carries a `fixture.yml` documenting the
fixture the family relies on (see `spec/integration/README.md`). All 11
dependency-graph edges now have an L2 family (waves 3.1 parity-critical, 3.2
business flow, 3.3 secondary). The remaining S3 work is the consolidation of
the cross-notion specs still parked under `spec/unit/integration/` into their
edge directories.

`support/` and `fixtures/` stay at the root of `brik/spec/` because they
are referenced by absolute path (`$BRIK_HOME/spec/support/...`) from
84+ specs. They remain shared between `_legacy/` and the four typed
layers.

## Target layers

| Layer | Scope | Tools | Per-test cost | Goal |
|---|---|---|---|---|
| **L0 Contracts** | One notion's I/O | JSON Schema + ShellSpec | < 100 ms | Verify a notion respects its static I/O contract |
| **L1 Unit** | Pure logic of one notion in isolation | ShellSpec, stubs/mocks | < 1 s | Verify if/else branches of a public function |
| **L2 Notion-pair** | One edge of the dependency graph | ShellSpec + minimal fixtures | 5-20 s | Verify a notion uses another correctly |
| **L3 Pipeline-E2E** | Whole graph + CI orchestrators | briklab (GitLab/Jenkins/local) | 2-7 min | Orchestrator parity + cases L2 cannot cover |

### L1 purity criterion

An L1 spec must run inside a minimal Alpine container: bash + jq + yq +
ShellSpec. If the spec needs `docker`, `kubectl`, `grype`, `npm`, a real
filesystem outside `/tmp`, or a real external service, **it belongs to
L2**.

## Writing a new test during the transition

- **Test of a pure function** of a notion → write the spec under
  `brik/spec/_legacy/<notion>/<submodule>_spec.sh` (current convention).
  It will migrate to `unit/<notion>/` when L1 is reorganised.
- **Test of an I/O contract** of a notion → write the spec under
  `brik/spec/contracts/<notion>_contract_spec.sh` and create / extend
  the schema under `brik/schemas/<notion>/v1/<output>.schema.json`.
- **Test of a graph edge** (e.g. "stage build dispatches correctly to
  the node stack") → write the spec under
  `brik/spec/integration/<edge>/` (create the directory if it is the
  first member of the family).

## Running the suite

```bash
# Everything (legacy + new layers)
cd brik && shellspec

# Per layer
shellspec spec/_legacy/         # transition
shellspec spec/contracts/       # L0
shellspec spec/unit/            # L1 (in progress)
shellspec spec/integration/     # L2 (in progress)
shellspec spec/pipeline-e2e/    # L3 (in progress)

# A specific notion (legacy)
shellspec spec/_legacy/stages/
```

## Known pre-existing failures

`shellspec spec/_legacy/` reports a stable count of failures located in
specs that manipulate `git tag` / `git init` inside temp directories
(`release_spec.sh`, `version_spec.sh`, `self_update_internals_spec.sh`,
`stages/release_spec.sh`). These tests are sensitive to the local git
environment (global config, git version, sandbox) and not caused by the
layered reorganisation. They are slated for cleanup as the affected
specs migrate to L1.

## References

- [Notion layout](layout.md)
- [Stage lifecycle](stage-lifecycle.md)
