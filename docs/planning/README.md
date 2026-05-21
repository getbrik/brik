# Planning reference

Technical reference for the Brik **planner**: the layer that turns
`(registry + changed files + flags)` into a reproducible `plan.json`
the three adapters (local, Jenkins, GitLab) consume identically.

This directory is the **deep reference** for contributors who write
adapters or extend the planner. If you only want a user-level
walkthrough of "what is a plan and how do I read one", read
[`docs/concepts/plan.md`](../concepts/plan.md) first and come back
here for field-by-field details.

## Reading order

| Page | Audience | What it covers |
|---|---|---|
| [`architecture.md`](architecture.md) | Anyone touching `lib/planning/` | How `changes.diff`, `impact.*`, `plan.compute`, `plan_writer.*` and `plan_reader.*` fit together. |
| [`plan.schema.md`](plan.schema.md) | Adapter author | Field reference for `plan.json` (mirrors `schemas/plan/v1/plan.schema.json`). |
| [`api.md`](api.md) | Adapter / runtime contributor | The `pipeline.plan.*` Bash API and `brik plan` CLI surface that consumers call. |
| [`modes.md`](modes.md) | Planner extender | Behavior contract for `safe`, `balanced`, and the deferred `aggressive` mode. |

## At a glance

```text
lib/transverse/changes.sh         <- normalize diff across GitLab / Jenkins / local
lib/planning/impact.sh            <- glob matching on the changed-file set
lib/planning/plan.sh              <- per-stage decide() + topo order + DAG edges
lib/planning/plan_writer.sh       <- serialize the compute stream to plan.json (+ sha256)
lib/planning/plan_reader.sh       <- pipeline.plan.* consumer API
lib/cli/plan.sh                   <- brik plan CLI (compute + --explain + --validate-only
                                     + plan gate sub-command)
schemas/plan/v1/plan.schema.json  <- JSON Schema 2020-12 contract
```

The planner is **pure compute**: it reads the registry (already loaded
in memory) plus `git diff`, decides run/skip per stage, and writes a
JSON document. No side effects on the workspace, no network calls.

## Reproducibility contract

Two invocations of `brik plan` against the same HEAD with the same
flags produce a **byte-identical** `plan.json`. This is enforced by:

1. `jq -S` sorts keys in the output.
2. `plan.dag.edges` outputs sorted edges (`LC_ALL=C sort -u`).
3. No timestamps are embedded.
4. The `fingerprint` is `sha256` of the canonical bytes with the
   fingerprint field replaced by `""`, then substituted in -- a
   round-trip self-hash idiom.

Tested by [`spec/integration/plan_reproducibility_spec.sh`](../../spec/integration/plan_reproducibility_spec.sh).

## Versioning

The plan format is frozen at `schemaVersion: v1` and pinned by the
[`schemas/plan/v1/plan.schema.json`](../../schemas/plan/v1/plan.schema.json)
JSON Schema. Adapters can rely on every field documented in
[`plan.schema.md`](plan.schema.md) being present across v0.6.x runtimes.

A future v2 would ship the new schema alongside v1; the runtime would
accept both during the deprecation window.

## Related material

- [`docs/concepts/plan.md`](../concepts/plan.md) -- user-facing
  walkthrough (what is a plan, how do I read one).
- [`docs/concepts/pipeline-context.md`](../concepts/pipeline-context.md)
  -- the `snapshot` / `release` context the planner stamps into
  `plan.json`.
- [`docs/registry/`](../registry/) -- the registry the planner reads
  from. Stages and stacks declare their `gate`, `impact`, and
  `runner_class` here.
- [ADR-001 -- manifest format](../../docs/adr/ADR-001-manifest-format.md)
  -- why YAML at author time, JSON at runtime.
