# Test Architecture

## TL;DR

The test suite is organised along the **11 domain notions** declared in
[`layout.md`](layout.md) and the inter-notion **dependency graph** documented
there. It is layered into four typed layers, all under
`brik/spec/{contracts,unit,integration,pipeline-e2e}/`:

- **L0 Contracts** -- does a notion's data match its JSON Schema? (shape only)
- **L1 Unit** -- is one notion's logic correct in isolation? (binaries mocked)
- **L2 Notion-pair** -- do two notions wire together correctly? (one real graph edge)
- **L3 Pipeline-E2E** -- does the whole flow run on a real platform? (briklab)

See [The four layers, explained](#the-four-layers-explained) for what each
layer tests, a concrete example, and why the split exists.

The former transition holding pen `spec/_legacy/` has been fully migrated and
removed: every spec now lives in its typed layer, and `spec/unit/` is purely
single-notion L1.

## Layout

```
brik/spec/
│
│   # Shared by every layer
├── spec_helper.sh                 # loaded by all specs: exports BRIK_HOME, BRIK_BIN, paths
├── support/                       # mock helpers (mock_helper.sh), used by 84+ specs
├── fixtures/                      # sample data: SARIF, JUnit, SBOM
│
├── contracts/                     # L0 - validate each notion's I/O against its JSON Schema
│
├── unit/                          # L1 - each notion's logic in isolation, binaries mocked
│   ├── stacks/                    #      one directory per notion...
│   ├── stages/
│   └── ...                        #      (deployments, planning, registry, transverse, cli, ...)
│
├── integration/                   # L2 - one directory per dependency-graph edge
│   ├── execution-env-x-stages/    #      --with-deploy reaches the deploy stage
│   ├── planning-x-stages/         #      plan.json drives each stage's run/skip
│   ├── registry-x-planning/       #      manifest gate.opt_in_flag drives the planner
│   ├── stages-x-stack/            #      build stage calls stacks.<stack>.build
│   ├── stages-x-package-manager/  #      package stage calls pkg.<registry>.publish
│   ├── stages-x-deployments/      #      deploy stage calls deploy.<target>.run
│   ├── stages-x-transverse/       #      stages read config / env / wait helpers
│   ├── stages-x-execution/        #      stage.run records the summary and status
│   ├── stack-x-package-manager/   #      stacks drive the npm / cargo / ... CLIs
│   ├── deployments-x-rollout/     #      a deploy target waits on rollout health
│   ├── findings-x-verify-stages/  #      shared severity + fix-classification
│   └── adapter-parity/            #      cross-cutting: adapters mirror registry/stacks
│
└── pipeline-e2e/                  # L3 - full pipelines on a real platform (briklab)
    └── plan_l3_local_spec.sh
```

Each `integration/<edge>/` directory carries a `fixture.yml` documenting the
fixture the family relies on (see `spec/integration/README.md`). All 11
dependency-graph edges have an L2 family. `adapter-parity/` holds cross-cutting
parity specs that are not a single edge (see its README).

`support/` and `fixtures/` stay at the root of `brik/spec/` because they are
referenced by absolute path (`$BRIK_HOME/spec/support/...`) from 84+ specs.

## The four layers, explained

Brik has no application UI -- it is shell libraries that drive real CI
platforms. Running the whole thing end to end is slow (minutes) and, when it
fails, does not tell you *which* piece broke. So the suite is split into four
layers, from cheap-and-isolated to expensive-and-realistic. Each answers a
different question. Together they form a pyramid: many fast tests at the
bottom (L0/L1), a handful of slow ones at the top (L3). The number in the name
(L0..L3) is simply how far you have zoomed out -- from a single data shape to a
whole pipeline on a real platform.

### L0 -- Contracts: "does the shape hold?"

**Question it answers:** does a notion's input/output match its published JSON
Schema?

An L0 test runs no business logic. It feeds sample data -- a
`<stage>-summary.json`, a `plan.json`, a stage manifest -- to its schema under
`brik/schemas/<notion>/v1/` and checks that valid samples pass and broken ones
(wrong enum value, missing field) are rejected.

- **Example:** `contracts/stages_contract_spec.sh` validates every
  `*-summary.json` shape against `schemas/stages/v1/stage-summary.schema.json`.
- **Cost:** < 100 ms. **How many:** ~one per notion.

### L1 -- Unit: "is the logic correct, in isolation?"

**Question it answers:** given controlled inputs, does one function of one
notion take the right branch and return the right value/exit code?

An L1 test loads a single notion's module and calls its functions directly
(`When call stacks.node.build ...`). Everything outside that notion is faked:
external binaries (`npm`, `kubectl`, `grype`, ...) are replaced by **mocks**, so
the test asserts *what the notion decides* (which command it builds, which exit
code it returns) without actually running the tool. This is where if/else
branches, error paths and edge cases get covered. It is the bulk of the suite.

- **Example:** `unit/stacks/node_spec.sh` mocks `npm` and checks that
  `stacks.node.install` runs `npm ci` when a lockfile is present.
- **Cost:** < 1 s. **How many:** most specs.

> **L1 purity rule.** An L1 spec must pass with only the brik prerequisites on
> PATH -- bash, jq, yq, jv, git, ShellSpec -- and **no stack/deploy tool
> installed** (this is exactly the CI runner). It mocks every external binary.
> If a spec needs a *real* binary, a real service, or a real filesystem outside
> `/tmp`, it is not a unit test -- it is L2 or L3. (Reference environment = the
> CI runner, not a bare busybox image; a few specs use GNU-coreutils behaviour
> such as `date`, which is fine.)

### L2 -- Notion-pair: "do two notions talk to each other correctly?"

**Question it answers:** when notion A uses notion B, does A call B correctly
and react correctly to B's result?

L1 fakes B; **L2 uses the real B.** Each L2 family targets one **edge of the
dependency graph** (the arrows in `layout.md`): the notions on both ends are
real, only the leaf binaries stay mocked. This catches wiring bugs that no
single-notion test can see -- the kind that previously needed a full pipeline
to surface.

- **Example:** `integration/execution-env-x-stages/` sets
  `BRIK_WITH_DEPLOY=true` and checks that `brik plan` really enables the deploy
  stage -- the cross-platform propagation bug, reproduced in ~1 s instead of a
  full GitLab+Jenkins run.
- **Cost:** 5-20 s. **How many:** one family per graph edge (11).

### L3 -- Pipeline-E2E: "does the whole thing work on a real platform?"

**Question it answers:** does the complete fixed flow run green on a real
orchestrator, and do the things only a live platform can prove actually hold?

L3 runs **full pipelines on real infrastructure** (briklab: real GitLab, real
Jenkins, real ArgoCD). It is reserved for what L2 cannot fake: orchestrator
parity (the same brik integrate behaves identically on GitLab and Jenkins) and real
deploy targets (GitOps sync, rollback). It is deliberately tiny because each
scenario is slow and a failure is hard to localise.

- **Example:** the GitLab `node-deploy-rollback` scenario deploys two versions
  and verifies ArgoCD rolls back to the previous image.
- **Cost:** 2-7 min. **How many:** 3-5 scenarios total (they live in briklab).

### Quick reference

| Layer | Question | Scope | Real vs faked | Cost | How many |
|---|---|---|---|---|---|
| **L0** Contracts | Shape valid? | one notion's I/O | schema only, no logic | <100 ms | ~1 per notion |
| **L1** Unit | Logic correct? | one notion, isolated | notion real, binaries mocked | <1 s | the bulk |
| **L2** Notion-pair | Wiring correct? | one graph edge | both notions real, leaf binaries mocked | 5-20 s | 1 per edge (11) |
| **L3** Pipeline-E2E | Works for real? | whole flow + platform | everything real | 2-7 min | 3-5 (in briklab) |

### Why split it this way

A bug should be caught by the **cheapest layer that can see it**, and a failure
should **name the culprit**. A wrong exit-code branch fails an L1 test in under
a second and points at the function. A bad hand-off between two notions fails
its L2 edge and points at the edge. Only genuinely platform-specific problems
reach L3. The old fixture-based E2E suite collapsed all of this into one slow
signal: an L1-class bug only showed up as "the node-complete pipeline is red",
minutes later, without saying which notion regressed.

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
