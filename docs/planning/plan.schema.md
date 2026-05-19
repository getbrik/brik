# `plan.json` field reference

Mirrors [`schemas/plan/v1/plan.schema.json`](../../schemas/plan/v1/plan.schema.json)
field by field, with the runtime semantics each adapter consumer can
rely on. The schema itself is authoritative -- this page exists so an
adapter author can read the contract without parsing JSON Schema.

## Top-level object

| Field | Type | Required | Constraint | Meaning |
|---|---|---|---|---|
| `schemaVersion` | string | yes | const `"v1"` | Plans tagged `v1` are accepted by every v0.6.x runtime. |
| `brikVersion` | string | yes | semver pattern | Informational; never used for gating. Lets adapters log which runtime produced the plan. |
| `context` | string | yes | enum `snapshot`, `release` | Resolved from `BRIK_COMMIT_TAG` at plan time. `release` when the env var is set; `snapshot` otherwise. |
| `mode` | string | yes | enum `safe`, `balanced`, `aggressive` | Selection mode. `aggressive` errors out in v0.6 -- it is reserved for the per-subproject impact graph deferred to v0.7+. |
| `workspace` | string | no | non-empty | Absolute path to the workspace root the plan was computed against. Informational. |
| `changes` | object | no | see [Changes block](#changes-block) | Snapshot of the changed-files set used by the planner. |
| `stages` | array | yes | min 1, unique | Per-stage plan entries in topological order. See [Stage entries](#stage-entries). |
| `dag` | object | yes | see [DAG block](#dag-block) | Adjacency list resolved from `spec.placement.{after,before}`. |
| `fingerprint` | string | yes | 64-hex sha256 | `sha256` of the canonical JSON with `fingerprint=""`. Lets adapters cache / short-circuit unchanged plans. |

## Changes block

```json
"changes": {
  "source": "local",
  "from_ref": "main",
  "to_ref":   "HEAD",
  "files":    []
}
```

| Field | Type | Required | Constraint | Meaning |
|---|---|---|---|---|
| `source` | string | yes | enum `gitlab`, `jenkins`, `local`, `none` | Which backend resolved the range. `none` means no diff basis was available (cold start). |
| `from_ref` | string | no | -- | Resolved base ref of the diff. Empty when `source=none`. |
| `to_ref` | string | no | -- | Resolved head ref of the diff. Empty when `source=none`. |
| `files` | array of string | yes | unique, items min length 1 | Snapshot of the changed-file set. Currently always emitted empty (v0.6) -- the planner consumes it internally but does not embed it for size reasons. Reserved for adapters that need to re-validate impact without re-running git. |

### Consumer rule for `source=none`

When `source=none`, every blocking stage must be marked `run` by
construction (the planner's cold-start safety net). Adapters that
re-derive selection from `changes` alone must respect this -- skipping
blocking stages on a cold start would defeat the conservative default.

## Stage entries

Each item in `stages[]`:

```json
{
  "id": "lint",
  "decision": "run",
  "reason": "impacted",
  "gate": {
    "mode": "blocking",
    "opt_in_flag": "--with-deploy",
    "contexts": ["snapshot", "release"]
  },
  "runner_class": "stack",
  "function": "stages.lint",
  "matched_globs": ["**/*.ts"]
}
```

| Field | Type | Required | Constraint | Meaning |
|---|---|---|---|---|
| `id` | string | yes | `^[a-z][a-z0-9-]*$` | Stage id (matches `metadata.id` in the manifest). |
| `decision` | string | yes | enum `run`, `skip` | Whether the adapter should dispatch the stage. |
| `reason` | string | yes | non-empty | Short machine-readable code. See [Reason codes](#reason-codes). |
| `gate.mode` | string | yes | enum `blocking`, `opt_in` | Mirrors the manifest `spec.gate.mode`. Adapters use this to decide if a skipped stage is hard-blocked or merely opted out. |
| `gate.opt_in_flag` | string | no | `^--[a-z][a-z0-9-]*$` | Present when `gate.mode=opt_in`. The CLI flag that flips this stage. |
| `gate.contexts` | array of string | no | unique | Present when the manifest restricts the stage to certain contexts. |
| `runner_class` | string | yes | enum `base`, `stack`, `scanner`, `analysis`, `deploy` | Which runner image the adapter should pick for this stage. |
| `function` | string | no | `^[a-z][a-z0-9_.]*$` | Dotted name of the Bash function that implements the stage. |
| `matched_globs` | array of string | no | unique, items min length 1 | Globs from `spec.impact.changes` (or the inherited stack impact set) that matched at least one entry in `changes.files`. Empty when the decision was derived from context alone. |

### Reason codes

The reason field is **machine-readable**: tools, CI annotations, and
reports can branch on the literal string. The taxonomy is closed: adding
a code is a planner change, not an adapter change.

| Code | When |
|---|---|
| `context-match` | `safe` mode, gate matched, no impact filter applied. |
| `context-mismatch` | `gate.contexts` is non-empty and does not include the active context. |
| `opt-in-flag-missing` | `gate.mode=opt_in` and the required `--with-*` flag was not passed. |
| `impacted` | `balanced` mode, at least one glob matched at least one changed file. |
| `no-impact` | `balanced` mode, declared globs but no changed file matched. |
| `no-impact-declared` | `balanced` mode, stage neither declares own globs nor inherits from the stack -- conservative run. |
| `no-diff` | Cold start: `changes.source=none`, conservative run. |
| `plan-test` | Reserved for adapter tests. Not emitted by the planner. |

## DAG block

```json
"dag": {
  "edges": [
    {"from": "build", "to": "lint"},
    {"from": "build", "to": "sast"},
    {"from": "lint",  "to": "package"}
  ]
}
```

| Field | Type | Required | Constraint | Meaning |
|---|---|---|---|---|
| `edges` | array of object | yes | unique items | Directed edges resolved from `spec.placement.{after,before}`. |
| `edges[].from` | string | yes | `^[a-z][a-z0-9-]*$` | Source stage id. |
| `edges[].to` | string | yes | `^[a-z][a-z0-9-]*$` | Destination stage id. |

Edges are sorted lexicographically by `(from, to)`. Two plans with the
same DAG produce the same `edges[]` sequence -- this is load-bearing
for fingerprint stability.

## Fingerprint

`fingerprint` is the `sha256` of the canonical JSON bytes of the plan
**with the fingerprint field replaced by `""`**. The serializer
computes it in three steps:

1. Build the plan object with `fingerprint=""`.
2. Hash the bytes (`sha256sum`).
3. Substitute the real hash in via `jq -S`.

Round-tripping a plan -- re-running `brik plan` against the same HEAD
with the same flags -- reproduces the same fingerprint. Adapters can
short-circuit downstream work when the fingerprint has not changed
across two pipelines on the same SHA.

## Adapter contract checklist

When writing a new adapter, the planner guarantees:

- [ ] `schemaVersion=="v1"`. Reject anything else with a clear error.
- [ ] Every stage from `registry.stage.list` appears in `stages[]`.
- [ ] `stages[].decision` is one of `run`, `skip` -- never anything else.
- [ ] When `changes.source=="none"`, every blocking stage is `run`.
- [ ] Two consecutive runs on the same SHA produce the same `fingerprint`.
- [ ] `dag.edges` is the source of truth for the DAG -- never recompute
      `after`/`before` from the manifest yourself.
