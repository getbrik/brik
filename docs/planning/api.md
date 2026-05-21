# Planning public API

The Bash functions and CLI surfaces that consumers of the planner are
allowed to call. Everything else (`plan.*`, `plan_writer.*`, the
internal stream format, `_plan_reader._resolve_path`, the
`cli.plan._render_*` helpers) is internal and may change without notice.

## The `pipeline.plan.*` Bash API

Sourced from `lib/planning/plan_reader.sh`. Safe to call after
`brik.use planning.plan_reader`. None of the functions perform I/O on
the workspace; they only read the resolved plan file.

### Plan file resolution

Every function below resolves the plan file in this order:

1. Explicit `<plan_file>` argument.
2. `BRIK_PLAN_FILE` environment variable.
3. `${BRIK_LOG_DIR}/plan.json`.
4. `${BRIK_WORKSPACE}/.brik-logs/plan.json`.
5. `${PWD}/.brik-logs/plan.json`.

When none of these exist, the API defaults to "run everything"
(`should_run` returns 0, other accessors return empty stdout with rc=0).
This is the **default** for pipelines that do not invoke the planner.

### Functions

| Function | Returns | Notes |
|---|---|---|
| `pipeline.plan.should_run <stage_id> [<plan_file>]` | rc=0 (run) / rc=1 (skip) | No stdout. Defaults to rc=0 when no plan exists. |
| `pipeline.plan.reason <stage_id> [<plan_file>]` | reason code on stdout | Empty when no plan exists or the stage is not listed. |
| `pipeline.plan.runner_class <stage_id> [<plan_file>]` | runner_class on stdout | Empty when no plan exists. Used by adapters to pick a runner image. |
| `pipeline.plan.gate <stage_id> [<plan_file>]` | gate.mode on stdout | `blocking` or `opt_in`. Empty when no plan exists. |
| `pipeline.plan.stages [<plan_file>]` | one id per line | Canonical stage order from the plan. Empty when no plan exists -- callers can fall back to `registry.stage.list`. |
| `pipeline.plan.fingerprint [<plan_file>]` | 64-hex sha256 | Empty when no plan exists. Lets adapters cache across pipelines. |
| `pipeline.plan.release_profile [<plan_file>]` | profile enum on stdout | Empty when no plan exists. |
| `pipeline.plan.release_version [<plan_file>]` | semver on stdout | Empty when no plan exists. |
| `pipeline.plan.is_candidate [<plan_file>]` | rc=0 (candidate) / rc=1 (not) | No stdout. rc=1 when no plan exists. |

### Convention notes

- Reading a stage that is not in `stages[]` returns empty stdout with
  rc=0 (treated as "run" for `should_run`). Callers that want a hard
  error wrap the call.
- All accessors are side-effect-free (no `report.record`, no file
  writes). The only function that writes to disk is `cli.plan.gate`
  (CLI sub-command, see below).
- The accessors all require `jq` to be on `PATH`. If `jq` is missing,
  `should_run` defaults to rc=0 (run) so a misconfigured runtime
  degrades to run-everything behavior rather than blocking the pipeline.

## The `brik plan` CLI

Sourced from `lib/cli/plan.sh`. Four surface forms:

### `brik plan` (compute mode)

```text
brik plan [--workspace <dir>] [--mode <m>] [--out <path>]
          [--with-release] [--with-package] [--with-deploy]
```

Defaults:

- `--workspace` -- `$BRIK_WORKSPACE` or `$PWD`.
- `--mode` -- read from `brik.yml`'s `pipeline.selection.mode`, falling
  back to `safe`.
- `--out` -- `${workspace}/.brik-logs/plan.json`.

Writes a `plan.json` and prints `plan: <path>` to stdout.

### `brik plan --explain`

Same compute as the default form, but pretty-prints a human-readable
summary instead of writing a file. Useful in PR comments and dev
loops:

```text
Brik plan (v1, brik 0.6.0)
  context     : snapshot
  mode        : balanced
  workspace   : /repo
  changes     : source=local range=main..HEAD
  fingerprint : 7b9c...

Stages:
  [ RUN ] init             context-match
  [ RUN ] build            impacted  (**/*.ts)
  [SKIP ] release          context-mismatch
```

### `brik plan --validate-only`

Computes the plan and validates the bytes against
`schemas/plan/v1/plan.schema.json` using `jv` (or `check-jsonschema`
as a fallback). On success prints `plan.json: valid against schema`
and exits 0. On failure exits with `BRIK_EXIT_INVALID_INPUT` (2).

Useful in CI before pushing a plan downstream: catches a planner
regression at the boundary rather than at the adapter that consumes it.

### `brik plan gate <stage_id> [--strict]`

Decides run/skip for `<stage_id>` against the active plan. Return
codes:

- **rc=0** -- the stage should run. Caller proceeds with
  `brik run stage <id>`.
- **rc=1** -- the stage should skip. The gate has already written a
  per-stage fragment to `brik-artifacts/<id>/<id>.json` with
  `tech.status=skipped`, `tech.kind=not-applicable`, and
  `business.reason=<plan reason>`, so the aggregate report still
  records the stage as a deliberate skip.
- **rc=2** -- usage error: no stage id given, or no plan file under
  `--strict`.

Without `--strict`, a missing plan file returns rc=0 (run) so
setups without a plan keep working. Adapters that **require** a plan to
exist pass `--strict` to fail loudly on a misconfigured pipeline.

## Idioms

### Local orchestrator: skip stages outside the plan

```bash
brik.use planning.plan_reader
brik.use registry

registry.use
mapfile -t stages < <(registry.stage.list)
for stage in "${stages[@]}"; do
    if ! pipeline.plan.should_run "$stage"; then
        reason="$(pipeline.plan.reason "$stage")"
        report.record "$stage" tech status   skipped
        report.record "$stage" tech kind     not-applicable
        report.record "$stage" business reason "$reason"
        continue
    fi
    stage.dispatch "$stage"
done
```

This is exactly what `pipeline.run` does today
([`lib/pipeline/pipeline.sh:275-291`](../../lib/pipeline/pipeline.sh)).
Adapters that orchestrate outside of `pipeline.run` (Jenkins Groovy,
GitLab job templates) call `brik plan gate <id>` from their host
context instead of sourcing the bash API.

### Adapter: pick a runner image per stage

```bash
class="$(pipeline.plan.runner_class "$stage")"
case "$class" in
    base)    image="${BRIK_RUNNER_BASE}" ;;
    stack)   image="$(registry.stack.runner_image "$BRIK_BUILD_STACK")" ;;
    scanner) image="${BRIK_RUNNER_SCANNER}" ;;
    *)       image="${BRIK_RUNNER_BASE}" ;;
esac
docker pull "$image"
```

### Adapter: short-circuit on unchanged plan

```bash
fp_now="$(pipeline.plan.fingerprint)"
fp_last="$(cat .brik-cache/last-fingerprint 2>/dev/null || true)"
if [[ "$fp_now" == "$fp_last" && -n "$fp_now" ]]; then
    log.info "plan unchanged since last run; skipping downstream rebuild"
    exit 0
fi
printf '%s\n' "$fp_now" > .brik-cache/last-fingerprint
```

## Versioning policy

The functions and CLI flags documented above are part of the v1 plan
contract: the format is frozen at `schemaVersion: v1`, a breaking
change ships under a parallel `v2` schema kept alongside `v1` for the
deprecation window. Removing or renaming a function is a breaking
change that requires that window. Adding a function (or a new optional
CLI flag) is a minor change.

The `spec/planning/`, `spec/cli/plan_*`, `spec/pipeline/pipeline_plan_*`
and `spec/integration/plan_*` test suites collectively exercise every
function and flag listed here against the builtin registry and a
synthetic plan fixture.
