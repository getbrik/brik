# Planning modes

The planner exposes three modes via `--mode <m>` (or
`pipeline.selection.mode` in `brik.yml`). Each mode is a contract for
what filters the planner applies before emitting a decision.

## Mode summary

| Mode | Context filter | Opt-in filter | Impact filter | Cold-start (no diff) |
|---|---|---|---|---|
| `safe` | yes | yes | no | run all (no filter to begin with) |
| `balanced` | yes | yes | yes (glob match) | run all (no-diff conservative) |
| `aggressive` | -- | -- | -- | -- (errors: deferred to v0.7+) |

The two filters above the impact filter (context + opt-in) are common
across `safe` and `balanced`; only the impact filter and the cold-start
fallback distinguish them.

## `safe` (default)

```text
for stage in stages:
    if gate.contexts is non-empty and active context not in gate.contexts:
        decision = skip, reason = context-mismatch
    elif gate.mode == opt_in and the --with-<x> flag was not passed:
        decision = skip, reason = opt-in-flag-missing
    else:
        decision = run, reason = context-match
```

**When to use:** the default for projects that have not yet declared
`spec.impact.*` globs in their stage manifests, or that want every
applicable stage to run on every commit (e.g. release pipelines).

**Trade-off:** zero risk of a false negative (no stage is skipped
because of an impact mismatch), but no time saved on doc-only or
unrelated commits.

## `balanced`

Same two filters as `safe`, then:

```text
if changes.source == "none":
    decision = run, reason = no-diff           # cold-start safety net
elif stage has no impact globs (own or inherited):
    decision = run, reason = no-impact-declared
elif any changed file matches any impact pattern:
    decision = run, reason = impacted
else:
    decision = skip, reason = no-impact
```

**When to use:** projects with stable `spec.impact.changes` declarations
on each stage (or `spec.impact.use_stack_impact` pointing at the
stack's source/test/build set). Cuts pipeline time on commits that
only touch docs, lockfiles unrelated to the stack, or scripts the
stage does not own.

**Trade-off:** a stage with no impact globs declared still runs (safe
fallback). Skipping requires explicit author intent in the manifest;
the planner never invents an impact relationship.

### Cold-start safety net

When `git diff` cannot resolve a base ref (fresh clone, brand-new
branch with no upstream), `changes.source` is set to `none` and the
planner emits `reason=no-diff` for every blocking stage. This keeps
balanced pipelines conservative on first-run: better to over-run than
to silently skip critical verification.

## `aggressive` (deferred)

```text
plan.compute --mode aggressive
# -> exits 64 (BRIK_EXIT_INVALID_INPUT)
# -> stderr explains: per-subproject impact graph is scheduled for v0.7+
```

The aggressive mode is reserved for a per-subproject impact graph (the
monorepo case: each subproject's stages only run if its own paths
changed). It is intentionally a hard error in v0.6 so users do not
configure it and silently get balanced behavior. Tracking:
[`docs/chantiers/20260518_refonte/analysis/monorepo-plan.md`](../chantiers/20260518_refonte/analysis/monorepo-plan.md).

## Reason taxonomy

Every decision is paired with a machine-readable reason code from this
closed set:

| Reason | Decision | Mode | Cause |
|---|---|---|---|
| `context-match` | run | safe | passed context + opt-in filters |
| `context-mismatch` | skip | safe + balanced | `gate.contexts` excludes the active context |
| `opt-in-flag-missing` | skip | safe + balanced | `gate.mode=opt_in` and `--with-<flag>` not passed |
| `impacted` | run | balanced | at least one impact glob matched |
| `no-impact` | skip | balanced | impact globs declared but no changed file matched |
| `no-impact-declared` | run | balanced | stage has no impact globs (conservative run) |
| `no-diff` | run | balanced | `changes.source=none` (cold start) |
| `plan-test` | run/skip | (test fixture) | reserved for hand-crafted adapter tests |

## Picking a mode for a new project

| Scenario | Recommended mode |
|---|---|
| First pipeline; no `spec.impact.*` declarations yet | `safe` |
| Stable monorepo subproject with declared impact globs | `balanced` |
| Release/tag pipelines (must run every blocking stage) | `safe` |
| Doc-only PRs in a busy repo | `balanced` (the planner skips lint/test/build with `no-impact`) |
| Multi-subproject monorepo with cross-cutting changes | `safe` until aggressive lands in v0.7+ |

## Switching modes safely

The plan fingerprint changes when the mode changes (the mode itself is
part of the hashed canonical bytes). Adapters that cache on the
fingerprint invalidate automatically. The schema enum is fixed; flipping
between `safe` and `balanced` never breaks an adapter or a downstream
consumer.

A `--mode` CLI override wins over `brik.yml`'s
`pipeline.selection.mode`, which itself wins over the planner's
internal default of `safe`. The override applies for the single
invocation only; nothing is persisted to disk except the chosen mode
in the resulting `plan.json`.
