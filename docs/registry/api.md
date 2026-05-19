# Registry public API

The Bash functions consumers of the registry are allowed to call.
Everything else (`_registry.*`, the loader cache, the JSON cache file
layout) is internal and may change without notice.

Source the API once at startup:

```bash
. "${BRIK_HOME}/lib/registry/registry.sh"
registry.use                       # idempotent; loads the cache on first call
```

After `registry.use` returns, all functions below are safe to call.
`registry.use` itself is the only function that performs I/O; the
accessors operate on in-memory arrays.

## Conventions

- All getters return data on stdout, one entry per line for lists.
- Boolean predicates return 0 / non-zero exit codes (no stdout).
- Looking up an unknown id returns rc=1 and an empty stdout. Callers
  that want a hard error wrap the call.
- Reading a missing optional field returns rc=0 with empty stdout.

## Stack accessors

| Function | Returns | Notes |
|---|---|---|
| `registry.stack.list` | one id per line | Sorted alphabetically. |
| `registry.stack.exists <id>` | rc=0 if exists | Use as a precondition. |
| `registry.stack.display_name <id>` | string | The `metadata.displayName`. |
| `registry.stack.markers <id>` | one path per line | `spec.detect.markers.any`. |
| `registry.stack.markers_glob <id>` | one glob per line | Globbed form of markers (handles bash glob expansion). |
| `registry.stack.cache_paths <id>` | one path per line | From `spec.cache.paths`. |
| `registry.stack.runner_image <id>` | image (no tag) | Returns the bare image ref. The version tag is fetched separately via `runner_default_version` / `runner_versions`. |
| `registry.stack.runner_default_version <id>` | string | `spec.runner.defaultVersion`. |
| `registry.stack.runner_versions <id>` | one version per line | `spec.runner.versions`. |
| `registry.stack.module <id>` | dotted path | The stack's Bash module path. |
| `registry.stack.api_required <id>` | one function per line | `spec.api.required`. |
| `registry.stack.api_optional <id>` | one function per line | `spec.api.optional`. |
| `registry.stack.doctor_tools <id>` | one binary per line | `spec.doctor.tools`. |
| `registry.stack.artifact_output_dirs <id>` | one dir per line | From `spec.artifacts.outputDirs`. |
| `registry.stack.artifact_patterns <id>` | one glob per line | From `spec.artifacts.patterns`. |
| `registry.stack.impact_source <id>` | one glob per line | `spec.impact.source`. |
| `registry.stack.impact_test <id>` | one glob per line | `spec.impact.test`. |
| `registry.stack.impact_build <id>` | one glob per line | `spec.impact.build`. |
| `registry.stack.detect <workspace>` | id on stdout, rc=0 on match | Walks `markers` for every stack. |
| `registry.stack.detect_from_framework <name>` | id on stdout, rc=0 on match | Reverse-lookup against `spec.frameworks.*`. |

## Stage accessors

| Function | Returns | Notes |
|---|---|---|
| `registry.stage.list` | one id per line | Topological order from `spec.placement`. |
| `registry.stage.exists <id>` | rc=0 if exists | Alias-aware: resolves `replaces` first. |
| `registry.stage.resolve_alias <id>` | id on stdout | Returns the canonical id when `<id>` is an alias. |
| `registry.stage.display_name <id>` | string | `metadata.displayName`. |
| `registry.stage.function <id>` | dotted name | `spec.function`. |
| `registry.stage.module <id>` | dotted path | `spec.module`. |
| `registry.stage.placement_slot <id>` | slot name | `spec.placement.slot`. |
| `registry.stage.placement_group <id>` | group name | `spec.placement.group`; empty if unset. |
| `registry.stage.after <id>` | one id per line | `spec.placement.after`. |
| `registry.stage.before <id>` | one id per line | `spec.placement.before`. |
| `registry.stage.runner_class <id>` | class name | `spec.runner.class`. |
| `registry.stage.gate_mode <id>` | `blocking` / `opt_in` | `spec.gate.mode`. Context-only semantics is expressed via `spec.gate.contexts` rather than a third mode. |
| `registry.stage.gate_opt_in_flag <id>` | `--with-...` | `spec.gate.opt_in_flag`. |
| `registry.stage.gate_contexts <id>` | one context per line | `spec.gate.contexts`. |
| `registry.stage.is_destructive <id>` | rc=0 if true | Reads `spec.dry_run.destructive`. |
| `registry.stage.aliases <id>` | one alias per line | `spec.replaces`. |
| `registry.stage.api_required <id>` | one function per line | `spec.api.required`. |
| `registry.stage.impact_changes <id>` | one glob per line | `spec.impact.changes`. |
| `registry.stage.impact_use_stack_impact <id>` | `source` / `test` / `build` | `spec.impact.use_stack_impact`. |

## Introspection

| Function | Returns |
|---|---|
| `registry.explain` | Multi-line dump of every stack and stage with their resolved fields. Used by `brik doctor --explain-registry` for debugging. |

## Idioms

### Detect a stack and resolve its runner image

```bash
registry.use
stack="$(registry.stack.detect "${BRIK_WORKSPACE}")" || {
    log.error "no stack detected"
    return 1
}
image="$(registry.stack.runner_image "$stack")"
docker pull "$image"
```

### Iterate the stages in pipeline order

```bash
registry.use
mapfile -t stages < <(registry.stage.list)
for stage in "${stages[@]}"; do
    stage.dispatch "$stage" || break
done
```

### Resolve an alias before dispatch

```bash
canonical="$(registry.stage.resolve_alias "$user_input")"
if ! registry.stage.exists "$canonical"; then
    log.error "unknown stage: $user_input"
    return "$BRIK_EXIT_INVALID_INPUT"
fi
```

### Guard a stage by `gate.mode` and `gate.contexts`

```bash
# 1. Context filter (applies to both modes when contexts is non-empty).
contexts="$(registry.stage.gate_contexts "$stage")"
if [[ -n "$contexts" ]]; then
    grep -qFx "$BRIK_CONTEXT" <<<"$contexts" || return 0  # skip
fi

# 2. Mode filter.
case "$(registry.stage.gate_mode "$stage")" in
    blocking) ;;  # always runs (within the context filter above)
    opt_in)
        flag="$(registry.stage.gate_opt_in_flag "$stage")"
        [[ "${BRIK_WITH_OPTS:-}" == *"$flag"* ]] || return 0  # skip
        ;;
esac
```

The planner (`brik plan`) runs this gate logic centrally; consumers
that bypass the planner replicate the same case.

## Versioning policy

The function signatures above are part of the v1 contract pinned by
[ADR-002](../../docs/adr/ADR-002-contract-testing.md). Removing or
renaming a function is a breaking change that requires a deprecation
window. Adding a function is a minor change.

The `spec/registry/contract/` test harness exercises every function
listed here against both the builtin manifests and a synthetic
extension manifest. Any new public function added to `registry.sh`
must come with a contract test.
