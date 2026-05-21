# Stage manifest reference

Field-by-field reference for `lib/registry/manifests/stages/<id>.yml`.

The authoritative contract is
[`schemas/registry/v1/stage.schema.json`](../../schemas/registry/v1/stage.schema.json).
Read this page for the meaning of each field and the consumer that
reads it.

## Skeleton

```yaml
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: my-stage
  displayName: My Stage
spec:
  module: stages.my_stage          # Bash module path
  function: stages.my_stage         # function to invoke
  placement:
    slot: lint                      # logical position in the fixed flow
    after: [build]
    before: [package]
  runner:
    class: stack                    # stack | base | scanner | analysis | deploy
  gate:
    mode: opt_in                    # always | opt_in | context_only
    opt_in_flag: --with-my-stage
    contexts: [snapshot, release]
```

`apiVersion`, `kind`, `metadata`, `spec` are required. Within `spec`,
`module`, `function`, `placement`, and `runner` are the load-bearing
fields every stage declares; the rest are optional but commonly used.

## metadata

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | kebab-case (`^[a-z][a-z0-9-]*$`). Surface name (`brik run stage <id>`). |
| `displayName` | string | yes | Human-readable. Surfaced in CLI, report. |
| `owner` | string | no | Free-form. |
| `minBrikVersion` / `maxBrikVersion` | semver | no | Same semantics as for stacks. |

## spec.module + spec.function

The Bash module path and the function inside it that implements the
stage.

```yaml
module: stages.release
function: stages.release
```

The dispatcher does roughly:

```bash
brik.use "$module"                 # source the file
"$function" "$@"                   # invoke
```

By convention, `module` and `function` carry the same dotted path so
that `brik.use stages.release` ends up sourcing `lib/stages/release.sh`
which defines `stages.release`. The fields are kept separate so a
manifest can point at a function with a different name (e.g. a
re-export from an extension that wraps a builtin).

## spec.placement

Where the stage sits in the fixed flow.

```yaml
placement:
  slot: lint                       # logical group (governs parallelism)
  after: [build]
  before: [package]
  group: verify                    # optional, for the "Verify" umbrella in GitLab
```

| Field | Semantics |
|---|---|
| `slot` | Conceptual position. The compiler uses it as a coarse rank; `after`/`before` refine it. Slot names mirror the fixed flow (`init`, `release`, `build`, `lint`, `sast`, `scan`, `test`, `package`, `container-scan`, `deploy`, `notify`). |
| `after` | List of stage ids this stage must follow. |
| `before` | List of stage ids this stage must precede. |
| `group` | Logical bundle. GitLab maps groups to umbrella jobs (the four verify-stage stages share `group: verify`). |

Stages in the same slot with no `after`/`before` between them are
free to run in parallel on platforms that support it (GitLab matrix,
Jenkins parallel).

The compiler resolves all placements into a total order accessible
via `registry.stage.list` and field
`registry.stage.placement_rank <id>`. Cycles abort the compile with
the offending path.

## spec.runner

Which container image class runs this stage.

```yaml
runner:
  class: stack                     # stack | base | scanner | analysis | deploy
```

| Class | Image | Used by |
|---|---|---|
| `stack` | `brik-runner-<stack>` chosen at runtime | build, test, package |
| `base` | `brik-runner-base` | init, release, notify |
| `scanner` | `brik-runner-scanner` | scan, container-scan, lint (when in scanner mode) |
| `analysis` | `brik-runner-analysis` | sast |
| `deploy` | `brik-runner-deploy` | deploy |

The wrapper resolves the actual image via
`pipeline.runner_image_for <runner_class> [<stack_id>]`. Extensions
that need a custom image declare a new class via `compatibility`
(below) or ship their own value and document it.

## spec.gate

Whether the stage runs by default.

```yaml
gate:
  mode: opt_in                     # blocking | opt_in
  opt_in_flag: --with-release      # required when mode = opt_in
  contexts: [release]              # optional, restricts to listed contexts
```

| `mode` | Behaviour |
|---|---|
| `blocking` | Stage runs whenever the current `context` matches `contexts` (or unconditionally if `contexts` is empty). |
| `opt_in` | Stage is skipped unless the planner is called with `opt_in_flag` (e.g. `--with-release`) OR `BRIK_WITH_<NAME>=true` is set. |

`contexts` lists the pipeline contexts that allow the stage. The
runtime context is derived from `BRIK_COMMIT_TAG` (`release` if set,
`snapshot` otherwise) by `_pipeline.detect_metadata`. A stage with
`contexts: [release]` outside a tag pipeline is skipped with reason
`context-mismatch` -- this is how "release-only" semantics is encoded
without a separate gate mode.

## spec.dry_run

Tells the runtime if the stage performs destructive actions that must
be no-ops under `BRIK_DRY_RUN=true`.

```yaml
dry_run:
  destructive: true                # deploy, release tagging, registry push
```

Stages marked `destructive: true` short-circuit early under dry-run
and still emit their fragment so the aggregate report stays complete.
Non-destructive stages run normally.

## spec.impact

Glob lists that influence the planner's per-stage impact decision.

```yaml
impact:
  changes:
    - "**/Dockerfile"
    - "**/package-lock.json"
```

A stage with `impact.changes` runs when the diff touches at least one
matching path. Stages without `impact.changes` either always run
(`gate.mode: always`) or rely on opt-in / context filters.

The flag `impact.use_stack_impact: true` (boolean) makes the planner
delegate to the active stack's `spec.impact.source` instead of
declaring stage-local globs. Used by `build`, `lint`, `test` so the
node stack's source globs propagate to every code-touching stage.

## spec.consumes + spec.provides

Document the data contract between stages. Currently informational
(used by `registry.explain` and the HTML report). A future planner
release will use these for parallelism graph resolution.

```yaml
consumes: [pipeline.context]
provides: [release.tag, release.version]
```

Keys are dotted paths into the dotenv outputs each stage emits.

## spec.artifacts

What the stage writes to disk for downstream stages.

```yaml
artifacts:
  paths:
    - brik-artifacts/scan/
  dotenv: true                     # also emits a key=value file
```

| Field | Semantics |
|---|---|
| `paths` | Directories the stage writes (`brik-artifacts/<stage>/` is the convention). Consumers (`stash`, GitLab `artifacts:`, Jenkins `archiveArtifacts`) read this list. |
| `dotenv` | When true, the stage emits `.brik-logs/<stage>.env` to be sourced by the next stage. |

## spec.api

Bash function exports the stage's module must declare. Same idea as
for stacks: the loader checks `declare -f` for each.

```yaml
api:
  required: [stages.release]
  optional: [stages.release.preflight]
```

## spec.replaces

Stage-level aliases. When a manifest declares `replaces: [old-name]`,
the runtime treats `brik run stage old-name` as
`brik run stage <new-id>`. Used during migrations where a stage was
renamed but consumers still reference the old name.

```yaml
replaces: [quality]                # lint stage absorbed the old "quality" stage
```

`registry.stage.aliases <id>` returns the list. The dispatcher
consults it before failing with "unknown stage".

## spec.compatibility

Declares cross-stage compatibility requirements. Used by extensions
that depend on a specific runtime range.

```yaml
compatibility:
  minBrikVersion: "0.6.0"
  requiresStages: [init, release]   # refuse to load if these stages are absent
```

## Worked example: the release manifest

```yaml
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: release
  displayName: Release
spec:
  module: stages.release
  function: stages.release
  placement:
    slot: release
    after: [init]
    before: [build]
  runner:
    class: base
  gate:
    mode: opt_in
    opt_in_flag: --with-release
    contexts: [release]
  dry_run:
    destructive: true
  impact:
    changes:
      - "**/*"
  consumes: [pipeline.context]
  provides: [release.tag, release.version]
  artifacts:
    paths: [.brik-logs/release-info.env]
    dotenv: true
  api:
    required: [stages.release]
```

All 11 builtin stage manifests live in
`lib/registry/manifests/stages/*.yml`. They are the canonical examples
to copy from when authoring a new stage.
