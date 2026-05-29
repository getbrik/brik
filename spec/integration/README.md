# L2 Notion-pair tests (integration layer)

This is the **L2** layer of the four-layer test architecture
(`docs/internals/test-architecture.md`), introduced by chantier
`docs/chantiers/20260528_e2e-tests-par-notion.md` (sprint S3).

One directory = **one edge of the dependency graph** documented in
`docs/internals/layout.md`. A spec here exercises how one notion uses
another for real (the notion under test is NOT stubbed); only third-party
binaries (`docker`, `kubectl`, `npm`, ...) may be stubbed. Target cost per
test: 5-20 s.

## Directory naming

`<source-notion>-x-<target-notion>/` for a directed edge, e.g.
`execution-env-x-stages/`, `planning-x-stages/`, `registry-x-planning/`.

## fixture.yml convention

Each edge directory carries a `fixture.yml` that documents the fixture(s)
the specs rely on, so a fixture cannot drift silently (risk R3 of the
chantier; cf. divergence D4 where a CVE hidden in `node-complete`
invalidated `expect: pass`). When the workspace is synthesized at runtime
(git init + a couple of source files), `fixture.yml` records what is
synthesized rather than committing a nested git repo.

```yaml
edge: <source> -> <target>          # human-readable edge
graph_edge_id: <n>                  # number from the chantier edge table
case: <one line: what behavior this family asserts>
synthesized_workspace:              # what setup() builds at runtime
  stack: node
  files: [package.json, brik.yml]
  git: init + single baseline commit
deps_expected: [git, jq, yq]        # external tools the spec needs
version_pin:                        # what the assertion is pinned to
  brik_schema: plan/v1
  registry: built-in manifests
covers_divergence: <id or "-">      # e2e-cross-platform divergence, if any
```

## Running

```bash
shellspec spec/integration/                       # whole L2 layer
shellspec spec/integration/execution-env-x-stages/
```

## Status (S3 -- all 11 edges landed)

Landed: parity-critical edges (3.1), business edges of the fixed flow (3.2),
and the secondary edges (3.3).

| Edge | Dir | Covers |
|---|---|---|
| #1 Execution env -> Stages | `execution-env-x-stages/` | D1: `--with-deploy` opt-in propagation |
| #10 Planning -> Stages | `planning-x-stages/` | plan.json drives the per-stage gate |
| #11 Registry -> Planning | `registry-x-planning/` | manifest `gate.opt_in_flag` consumed by the planner |
| #2 Stages -> Stack | `stages-x-stack/` | build stage -> real `stacks.<stack>.build` (relocated) |
| #3 Stages -> Package manager | `stages-x-package-manager/` | package stage -> `pkg.<reg>.publish` (relocated) |
| #4 Stages -> Deployments | `stages-x-deployments/` | deploy stage -> `deploy.<target>.run`; unknown target rejected |
| #5 Stages -> Transverse | `stages-x-transverse/` | config.get / env.resolve_indirect / wait.until contract |
| #6 Stages -> Execution | `stages-x-execution/` | stage.run instrumentation (summary + aggregate tech.status) |
| #9 Stack -> Package manager | `stack-x-package-manager/` | stacks drive npm ci / cargo build with expected args |
| #8 Deployments -> Rollout | `deployments-x-rollout/` | health gate timeout (exit 8) + strategy delegation |
| #7 Findings x verify stages | `findings-x-verify-stages/` | shared severity scale + per-stage fix-classification |

All 11 dependency-graph edges now have an L2 family. The `adapter-parity/`
directory holds cross-cutting parity specs (adapters mirroring the
registry/stacks) that are not a single edge -- see its own README. The
cross-notion specs that used to live under `spec/unit/integration/` have been
relocated here (into edge directories or `adapter-parity/`) or into
`spec/pipeline-e2e/` for the full plan-driven pipeline run, so `spec/unit/` is
now purely single-notion L1.
