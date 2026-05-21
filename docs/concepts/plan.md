# Plan

A Brik **plan** is a reproducible record of which stages will run for a
given commit, why, and on what input. It is the single source of truth
shared by the local wrapper, Jenkins, and GitLab adapters: same commit,
same plan, same outcome -- no matter which adapter executes it.

## Anatomy

`brik plan --out .brik-logs/plan.json` produces a document validated
against [`schemas/plan/v1/plan.schema.json`](../../schemas/plan/v1/plan.schema.json):

```json
{
  "schemaVersion": "v1",
  "brikVersion": "0.6.0",
  "context": "snapshot",
  "mode": "balanced",
  "workspace": "/path/to/repo",
  "changes": {
    "source": "local",
    "from_ref": "main",
    "to_ref": "HEAD",
    "files": []
  },
  "stages": [
    {
      "id": "init",
      "decision": "run",
      "reason": "context-match",
      "gate": { "mode": "blocking" },
      "runner_class": "base",
      "function": "stages.init",
      "matched_globs": []
    }
  ],
  "dag": {
    "edges": [
      { "from": "build", "to": "lint" }
    ]
  },
  "fingerprint": "0394539b236e097b88b9c8072397a2f214e7a4107ba2823802872582b11f085e"
}
```

Key fields:

| Field | Meaning |
|---|---|
| `context` | `snapshot` for tag-less commits, `release` when `BRIK_COMMIT_TAG` is set. Mirrors the `pipeline.context` concept. |
| `mode` | `safe` (default), `balanced`, or `aggressive` (not yet implemented; currently errors). |
| `stages[].decision` | `run` or `skip`. |
| `stages[].reason` | Machine-readable code: `context-match`, `context-mismatch`, `opt-in-flag-missing`, `no-impact`, `no-impact-declared`, `no-diff`, `impacted`. |
| `stages[].gate.mode` | `blocking` or `opt_in`, mirroring the manifest's `spec.gate.mode`. |
| `dag.edges` | Adjacency list resolved from `spec.placement.{after,before}`. Sorted lexicographically. |
| `fingerprint` | sha256 of the canonical JSON with `fingerprint` set to `""`. Two identical plans share the fingerprint. |

The document is **byte-reproducible** (jq -S sorts keys, the DAG is
sorted, no timestamps are embedded). Two invocations against the same
HEAD with the same flags produce strictly identical bytes.

## Three planning modes

| Mode | What it filters on | Use case |
|---|---|---|
| `safe` | Context only (`gate.contexts`) and opt-in flags | Default. Runs every blocking stage applicable to the current context. |
| `balanced` | Above + per-stage impact globs vs the changed-file set | Skip a stage when none of the changed files match its `spec.impact.changes` (or the inherited `spec.impact.use_stack_impact` set). |
| `aggressive` | Per-subproject impact graph | **Not yet implemented.** The planner returns rc=64 with an actionable message. |

Set the default mode for a project in `brik.yml`:

```yaml
pipeline:
  selection:
    mode: balanced
    stages:
      # Optional per-stage glob overrides (not yet wired into the
      # planner -- the registry's spec.impact wins).
      lint:
        changes: ["src/**/*.ts"]
```

Override at the CLI with `brik plan --mode <m>`.

## Where the plan lives

| Adapter | Path |
|---|---|
| Local (`brik run pipeline --auto-select`) | `${BRIK_WORKSPACE}/.brik-logs/plan.json` |
| Jenkins (`brikPipeline`) | `${WORKSPACE}/.brik-logs/plan.json`, exposed as `BRIK_PLAN_FILE` |
| GitLab | the `brik-plan` job artifact at `.brik-logs/plan.json` |

The `pipeline.plan.*` API in [`lib/planning/plan_reader.sh`](../../lib/planning/plan_reader.sh)
is the consumer interface:

```bash
pipeline.plan.should_run <stage>     # 0 if run, 1 if skip, default run when no plan
pipeline.plan.reason     <stage>     # the reason code
pipeline.plan.runner_class <stage>   # which runner image the adapter should pick
pipeline.plan.gate       <stage>     # gate.mode
pipeline.plan.stages                 # canonical stage order from the plan
pipeline.plan.fingerprint            # sha256 of the current plan
```

## Producing a plan

```bash
brik plan --out .brik-logs/plan.json          # default: safe mode
brik plan --explain                            # human summary, no file
brik plan --mode balanced --with-deploy        # flip a stage's opt-in
brik plan --validate-only                      # produces a plan, validates schema, discards
brik plan gate lint                            # 0/1 per stage; on skip, writes the
                                               # not-applicable fragment for the report
```

## Consuming a plan from the orchestrator

In the bash runtime, `pipeline.run` honors `BRIK_PLAN_FILE`
automatically: when set, the in-process gatekeeper skips every stage
the plan marks `skip` and records a `not-applicable` fragment with the
plan's reason. Without the env var, the runtime behaves exactly like
the pre-planner runtime (the gate is a no-op).

In Jenkins (`brikPipeline.groovy`), each downstream stage runs through
`planSaysRun(<id>)` -- a `sh "brik plan gate <id>"` round-trip. A
skipped stage stays in the Stage View as "skipped per plan" and its
fragment is still stashed so `brik-notify` aggregates it.

In GitLab, the `brik-plan` job computes the plan and every stage job
sources `/tmp/brik-plan-gate.sh <id>` -- the same `brik plan gate`
round-trip as Jenkins. A skipped stage shows as a green "skipped (per
plan)" job and its not-applicable fragment is uploaded so `brik-notify`
aggregates it into the final report.

## Adding a stage to the plan

Drop a manifest under `lib/registry/manifests/stages/<id>.yml` (or a
user dir referenced via `BRIK_REGISTRY_EXTENSIONS_DIRS`), provide a
matching Bash function, and re-run `brik plan` -- the new stage shows
up in the topological order automatically. Full walkthrough:
[`docs/operations/extensions.md`](../operations/extensions.md).
