# Stage manifest reference

Field-by-field reference for `lib/registry/manifests/stages/<id>.yml`.

The authoritative contract is
[`schemas/registry/v1/stage.schema.json`](../../../schemas/registry/v1/stage.schema.json).
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
    slot: verify                    # logical position in the fixed flow
    after: [build]
    before: [package]
  runner:
    class: stack                    # stack | base | scanner | analysis | deploy
  gate:
    mode: opt_in                    # blocking | opt_in
    opt_in_flag: --with-my-stage
    contexts: [snapshot, release]
```

`apiVersion`, `kind`, `metadata`, `spec` are required. Within `spec`,
`module`, `function`, `placement`, and `runner` are the load-bearing
fields every stage declares; the rest are optional but commonly used.

## metadata

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | kebab-case (`^[a-z][a-z0-9-]*$`). Surface name (`brik stage <id>`). |
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
  slot: verify                     # logical group (governs parallelism)
  after: [build]
  before: [package]
  group: verify                    # optional, for the "Verify" umbrella in GitLab
```

| Field | Semantics |
|---|---|
| `slot` | Conceptual position. The compiler uses it as a coarse rank; `after`/`before` refine it. Slot names come from the schema enum (`init`, `release`, `pre-build`, `build`, `post-build`, `verify`, `pre-package`, `package`, `post-package`, `pre-deploy`, `deploy`, `post-deploy`, `notify`); the four quality stages share `slot: verify`. |
| `after` | List of stage ids this stage must follow. |
| `before` | List of stage ids this stage must precede. |
| `group` | Logical bundle. GitLab maps groups to umbrella jobs (the four verify-stage stages share `group: verify`). |

Stages in the same slot with no `after`/`before` between them are
free to run in parallel on platforms that support it (GitLab matrix,
Jenkins parallel).

The loader resolves all placements into a total order accessible via
`registry.stage.list`: that ordered list is the only thing exposed,
there is no per-stage rank accessor. The topological sort applies a
depth fallback rather than aborting, so an unresolvable `after`/`before`
edge sorts the stage last instead of failing the load.

## spec.runner

Which container image class runs this stage.

```yaml
runner:
  class: stack                     # stack | base | scanner | analysis | deploy
```

| Class | Image | Used by |
|---|---|---|
| `stack` | `brik-runner-<stack>` chosen at runtime (dynamic) | build, test, package |
| `base` | `brik-runner-base` | init, release, notify |
| `scanner` | `brik-runner-scanner` | scan, container-scan, lint (when in scanner mode) |
| `analysis` | `brik-runner-analysis` | sast |
| `deploy` | `brik-runner-deploy` | deploy |

The class-to-image mapping is centralized in
[`lib/registry/runner_classes.yml`](../../concepts/runner-classes.md) (the single
source of truth) and resolved via `registry.runner_class.image <class>`.
The four static classes (`base`/`analysis`/`scanner`/`deploy`) declare an
`image` + `tag`; the `stack` class is dynamic (`image_env: BRIK_CI_IMAGE`,
computed by the init stage from the project stack). Extensions that need a
custom image add a class to that file or override every class at once via
`BRIK_RUNNER_CLASSES_FILE`. See [runner-classes.md](../../concepts/runner-classes.md).

## spec.gate

Whether the stage runs by default.

```yaml
gate:
  mode: opt_in                     # blocking | opt_in
  opt_in_flag: --with-release      # required when mode = opt_in
  contexts: [release]              # required, restricts to listed contexts
```

| `mode` | Behaviour |
|---|---|
| `blocking` | Stage runs whenever the current `context` matches one of `contexts` (which is required and non-empty; a stage that should always run lists every context, e.g. `[snapshot, release]`). |
| `opt_in` | Stage is skipped unless the planner is called with `opt_in_flag` (e.g. `--with-release`) OR `BRIK_WITH_<NAME>=true` is set. |

`contexts` lists the pipeline contexts that allow the stage. The
runtime context is derived from `BRIK_COMMIT_TAG` (`release` if set,
`snapshot` otherwise) by `_pipeline.detect_metadata`. A stage with
`contexts: [release]` outside a tag pipeline is skipped with reason
`context-mismatch`: this is how "release-only" semantics is encoded
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
matching path. Stages without `impact.changes` either run on every
applicable context (`gate.mode: blocking`) or rely on opt-in / context
filters.

The field `impact.use_stack_impact` is a string enum (`source`,
`test`, or `build`) that makes the planner delegate to the named glob
set on the active stack's `spec.impact` instead of declaring
stage-local globs. Used by `build`, `lint`, `test` so the node stack's
source globs propagate to every code-touching stage.

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

## metadata.aliases

Stage-level aliases. `metadata.aliases` is an array of alternate ids;
when a manifest declares them, the runtime treats `brik stage
<alias>` as `brik stage <canonical-id>`. Used during migrations
where a stage was renamed but consumers still reference the old name.

```yaml
metadata:
  id: lint
  displayName: Lint
  aliases: [quality]               # lint stage absorbed the old "quality" stage
```

`registry.stage.aliases <id>` returns the list. The dispatcher
consults it before failing with "unknown stage".

## spec.replaces

`spec.replaces` is a separate, single-string field naming one stage
this manifest supersedes. It is not a list and not an alias map. A
manifest that declares `spec.replaces` **must** also declare
`spec.compatibility` (the schema requires the pair) so the runtime can
verify the replacement honors the same contract as the stage it
replaces.

```yaml
spec:
  replaces: legacy-scan            # single string, not a list
  compatibility:
    mustProvideSameAs: legacy-scan
```

## spec.compatibility

Declares the contract a replacing stage must honor. Required whenever
`spec.replaces` is set. The schema allows exactly two keys:

```yaml
compatibility:
  mustProvideSameAs: legacy-scan    # this stage must provide everything the named stage provides
  provides: [scan.report]           # capabilities this stage guarantees to emit
```

| Field | Semantics |
|---|---|
| `mustProvideSameAs` | A stage id. The replacing stage must provide at least every capability the named stage provides. |
| `provides` | Explicit list of dotted capability keys this stage emits. |

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
