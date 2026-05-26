#!/usr/bin/env bash
# @module cli.registry
# @description CLI surface for the Brik registry. Exposes the per-stage
#   structural data (id, display_name, runner_class, parallel_group,
#   needs) as JSON so adapters (Jenkins brikDriver, future GitHub
#   actions, ...) can iterate the canonical stage list at runtime
#   without hardcoding it. The GitLab adapter does not consume this
#   command directly (its YAML jobs are static) but the same data
#   drives the parity specs that verify the YAML against the registry.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_REGISTRY_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_REGISTRY_LOADED=1

cli.registry.run() {
    brik.use cli.helpers
    brik.use registry.registry

    if [[ $# -eq 0 ]]; then
        cli.registry._usage
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local subcommand="$1"; shift
    case "$subcommand" in
        stages) cli.registry.stages "$@" ;;
        *)
            brik_usage_error "unknown registry subcommand: $subcommand" || return "$?"
            ;;
    esac
}

cli.registry._usage() {
    cat <<'EOF'
usage: brik registry <subcommand>

Subcommands:
  stages [--format json]   Emit the per-stage structural list as JSON.
EOF
}

# Emit the per-stage structural list as JSON.
#
# Each entry carries:
#   id              canonical stage id (from manifest metadata.id)
#   display_name    human-readable label (from manifest metadata.displayName)
#   runner_class    OCI image class (from manifest spec.runner.class)
#   parallel_group  placement.slot value (stages sharing a slot run in parallel)
#   needs           topological dependencies (from placement.after)
#
# Order matches registry.stage.list (topological sort cached by the registry
# loader).
#
# Usage: brik registry stages [--format json]
cli.registry.stages() {
    local format="json"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) brik_require_arg "--format" "${2-}" || return "$?"
                      format="$2"; shift 2 ;;
            *)        brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    if [[ "$format" != "json" ]]; then
        printf '[brik registry stages] --format=%s is not supported (only json)\n' \
            "$format" >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    command -v jq >/dev/null 2>&1 || {
        printf '[brik registry stages] jq required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    }

    # Build the JSON array from registry accessors. Each entry is composed
    # in shell then concatenated; jq does the final pretty-print to ensure
    # the output is canonical valid JSON regardless of any quoting quirks.
    local stages_json="["
    local first=true
    local id
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        local entry
        entry="$(cli.registry._stage_entry "$id")" || return "$?"
        if $first; then
            stages_json+="$entry"
            first=false
        else
            stages_json+=",$entry"
        fi
    done < <(registry.stage.list)
    stages_json+="]"

    printf '%s\n' "$stages_json" | jq '.'
}

# Build a single JSON object for one stage id. Returns the JSON on stdout.
# Encoded with jq -n so the shape stays canonical and arrays/strings are
# safely escaped.
cli.registry._stage_entry() {
    local id="$1"
    local display_name runner_class parallel_group
    display_name="$(registry.stage.display_name "$id")"
    runner_class="$(registry.stage.runner_class "$id")"
    parallel_group="$(registry.stage.placement_slot "$id")"

    # needs[]: explicit predecessors from placement.after. Kept as-is
    # (no transitive expansion) because that is what an adapter wants
    # for building a job-level dependency graph.
    local needs_json="[]"
    local after_ids
    after_ids="$(registry.stage.after "$id" 2>/dev/null | grep -v '^$' || true)"
    if [[ -n "$after_ids" ]]; then
        needs_json="$(printf '%s\n' "$after_ids" | jq -R . | jq -s .)"
    fi

    jq -n \
        --arg id "$id" \
        --arg display_name "$display_name" \
        --arg runner_class "$runner_class" \
        --arg parallel_group "$parallel_group" \
        --argjson needs "$needs_json" \
        '{
            id: $id,
            display_name: $display_name,
            runner_class: $runner_class,
            parallel_group: $parallel_group,
            needs: $needs
        }'
}
