# `pipeline`

> Pipeline-level selection settings: how the planner decides which stages run.

**Section:** `pipeline` (optional) &nbsp;·&nbsp; **Schema:** [`brik.schema.json#$defs/pipeline`](../../../schemas/config/v1/brik.schema.json)

## What it is for

The flow is fixed, but not every stage runs on every commit. This section tunes
the [plan](../../concepts/plan.md): how aggressively Brik filters stages, and
which files each stage cares about.

## What it does

- **`selection.mode`** chooses the filtering strategy: `safe` keeps
  context-only filtering (the default), `balanced` adds per-file impact
  filtering from each stage's declared globs, and `aggressive` is reserved for a
  later version (the planner errors if it is requested).
- **`selection.stages`** supplements or replaces a stage's impact globs for this
  project only, keyed by stage id.

## When it runs

The planner reads this before any stage runs, to produce `plan.json`. It changes
*which* stages execute, never their order. See [the plan](../../concepts/plan.md).

## How to configure

`pipeline` is optional. The default is `mode: safe` with no per-stage overrides.

<!-- BEGIN AUTO-GENERATED: quick-reference -->
### `pipeline.selection`

| Field | Type | Default |
|-------|------|---------|
| `pipeline.selection.mode` | enum (`safe`, `balanced`, `aggressive`) | `safe` |
| `pipeline.selection.stages` | `object` | -- |

- **`pipeline.selection.mode`**

  safe = context-only filtering (default). balanced = adds per-file impact filtering using spec.impact.changes from stage manifests, with optional per-stage overrides under selection.stages. aggressive = per-subproject impact graph; reserved for v0.7+, planner errors with rc=64 if requested.

- **`pipeline.selection.stages`**

  Per-stage impact overrides. Map keyed by stage id (init, release, build, lint, sast, scan, test, package, container-scan, deploy, notify). Each value supplements or replaces the manifest's spec.impact.changes for THIS project only.


*Example*

```yaml
pipeline:
  selection:
    mode: balanced
```

<!-- END AUTO-GENERATED -->

### Examples

Enable per-file impact filtering, and tell the test stage which paths matter:

```yaml
pipeline:
  selection:
    mode: balanced
    stages:
      test:
        changes:
          - "src/**"
          - "tests/**"
```

## See also

- [The plan](../../concepts/plan.md) -- the per-commit decision this section tunes
- [Fixed flows](../../concepts/fixed-flows.md) -- the stages the plan selects from
- [`brik.yml` reference](README.md) -- all top-level sections
