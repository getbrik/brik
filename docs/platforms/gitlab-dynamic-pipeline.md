# GitLab dynamic child pipeline

The dynamic child pipeline is the recommended GitLab adapter for projects
that want impact-driven stage selection: docs-only commits skip the
build/lint/test grid without spinning up runner containers; release
contexts run the full flow as before.

This page covers migration from the legacy single-pipeline template to
the dynamic child template. Both templates ship side by side until
v0.8.x.

## At a glance

| Aspect            | Legacy `pipeline.yml`            | Dynamic `dynamic-pipeline.yml`        |
|-------------------|----------------------------------|---------------------------------------|
| Stages            | init, release, build, verify, package, post-verify, deploy, notify | plan + downstream (the child carries the legacy 8) |
| Selection         | `rules:` on every job            | `brik plan` produces a child YAML; skipped jobs are `rules:when:never` overrides |
| Plan reproducibility | none                          | byte-identical `plan.json`, sha256 fingerprint        |
| `resource_group:` | unchanged                        | unchanged - child re-uses legacy job names |
| `brik.yml`        | unchanged                        | unchanged                              |
| GitLab minimum    | 13.x                              | 14.0 (for `needs:pipeline:job:`)       |

## Migrate in one diff

```diff
 include:
-  - project: 'getbrik/brik'
-    ref: v0.6
-    file: '/shared-libs/gitlab/templates/pipeline.yml'
+  - project: 'getbrik/brik'
+    ref: v0.6
+    file: '/shared-libs/gitlab/templates/dynamic-pipeline.yml'
```

No `brik.yml` change is required. To pin the planning mode for the
project (default is `safe`), declare it explicitly:

```yaml
# brik.yml
pipeline:
  selection:
    mode: balanced   # safe | balanced | aggressive(v0.7+)
```

## How it works

1. **Parent pipeline** (the one triggered by a push) runs a single
   `brik-plan` job that:
   - executes the planner against `brik.yml` plus the diff returned by
     `lib/transverse/changes.sh` (GitLab maps the diff via
     `CI_COMMIT_BEFORE_SHA..CI_COMMIT_SHA`),
   - writes `.brik-logs/plan.json` (schema `schemas/plan/v1/plan.schema.json`),
   - emits the child pipeline YAML at `.brik-logs/generated-pipeline.yml`
     via `brik plan --format gitlab-child`,
   - records one not-applicable fragment per skipped stage so the final
     report includes every stage's outcome.

2. **Downstream trigger** uses GitLab's `trigger: include: artifact:`
   to spawn the child pipeline from the generated YAML.

3. **Child pipeline** is the legacy `pipeline.yml`, included verbatim,
   with `rules: when: never` overrides on each skipped job. The child's
   `brik-notify` job adds `needs: - pipeline: $CI_PARENT_PIPELINE_ID;
   job: brik-plan; artifacts: true` so it can aggregate the parent's
   skip fragments together with the child's own run fragments. The
   final `aggregate-report.{md,json}` contains every stage record with
   reason - skipped stages keep their `tech.kind=not-applicable` and
   `business.reason=<plan reason>` from the parent.

## Three scenarios

### Full release

```text
git push v1.2.3
```

- Plan: `release` context, every blocking stage runs, opt-in flags
  required for release/package/container-scan/deploy/notify.
- Parent: 1 job (`brik-plan`).
- Child: 8 jobs run; no skip overrides.
- Total wall-clock: unchanged vs legacy.

### Docs-only commit

```text
git commit -am "docs: clarify section X"; git push
```

- Plan: `snapshot` context, `balanced` mode, no source file changed.
- Parent: 1 job (`brik-plan`) plus 5 skip fragments written.
- Child: only `brik-init` and `brik-notify` actually run.
- Aggregate-report: every stage records `tech.status=skipped`,
  `tech.kind=not-applicable`, `business.reason=<context-mismatch|
  opt-in-flag-missing|no-impact>`.
- Wall-clock: 3x to 5x speed-up depending on stack (the lint+test grid
  is the longest serial dependency).

### Invalid plan

If `brik plan` fails (e.g. an extension introduces a manifest typo),
the `brik-plan` job exits non-zero and the downstream trigger never
fires. The pipeline visibly fails on `brik-plan` with the planner's
diagnostic output - no silent fallback that would defeat the whole
contract.

## Resource groups and concurrency

The child pipeline inherits the parent's project, ref, and commit. Any
`resource_group:` declared on a legacy job (e.g. `production-deploy`)
continues to honor the same serialization semantics across parent runs
- the child's job name is identical to the legacy job name, so GitLab's
resource group bookkeeping ties them together.

Multiple parent pipelines on the same ref still serialize on those
resource groups, matching the behavior documented in
`briklab/docs/e2e-known-issues.md` under "parallel resource_group".

## Knobs

| Variable | Default | Purpose |
|---|---|---|
| `BRIK_GITLAB_TEMPLATES_PROJECT` | `getbrik/brik` | Project hosting the templates (override to point at a fork) |
| `BRIK_GITLAB_TEMPLATES_REF`     | `v0.6`         | Ref of the templates project the child includes |
| `BRIK_PLAN_FILE`                | _unset_        | Set automatically by the parent; the child reads it via `needs:` |
| `BRIK_DRY_RUN`                  | `false`        | Same semantics as the legacy pipeline |
| `BRIK_TAG`                      | _empty_        | Release tag; an explicit value flips the plan into release context |

## Roll back to legacy

If a project needs to disable plan-driven execution temporarily (e.g.
during a planner regression investigation), swap the include back to
`pipeline.yml`. The legacy template is unchanged and produces the same
output it did in v0.5.0.

## Known limits

- Requires GitLab >= 14.0 for `needs:pipeline:job:` (older versions need
  to fetch parent artifacts via a curl-based bootstrap; the
  documentation snippet is left as an exercise).
- `aggressive` mode (per-subproject impact graph) is deferred to v0.7+;
  see `docs/chantiers/20260518_refonte/analysis/monorepo-plan.md`.
- Child pipelines count against the project's CI minutes the same way
  parent pipelines do. The net minute saving comes from skipped jobs,
  not from a cheaper child pricing model.
