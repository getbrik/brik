#!/usr/bin/env bash
# @module publish
# @description Publish dispatcher for brik-lib. Delegates to target-specific modules.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_PUBLISH_LOADED:-}" ]] && return 0
_BRIK_CORE_PUBLISH_LOADED=1

# Validate that a secret variable name is set and the referenced variable has a value.
# Usage: _publish._require_secret_var <var_name> <label>
# Returns 7 if the variable name is empty or the referenced variable is unset.
_publish._require_secret_var() {
    local var_name="$1"
    local label="$2"

    if [[ -z "$var_name" ]]; then
        log.error "$label variable name is not configured"
        return 7
    fi

    if [[ -z "${!var_name:-}" ]]; then
        log.error "$label variable '$var_name' is not set or empty"
        return 7
    fi

    return 0
}

# Publish artefacts to a registry.
# Usage: publish.run --target <npm|docker|maven|pypi|cargo|nuget> [--dry-run]
publish.run() {
    local target="" dry_run="${BRIK_DRY_RUN:-}"
    local -a passthrough_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --dry-run) dry_run="true"; passthrough_args+=(--dry-run); shift ;;
            *) passthrough_args+=("$1"); shift ;;
        esac
    done

    if [[ -z "$target" ]]; then
        log.error "publish target is required (--target)"
        return 2
    fi

    log.info "publishing with target: $target"

    # Load and delegate to target-specific module
    brik.use "publish.${target}" || {
        log.error "unsupported publish target: $target"
        return 7
    }

    local publish_fn="publish.${target}.run"
    if ! declare -f "$publish_fn" >/dev/null 2>&1; then
        log.error "publish function not found: $publish_fn"
        return 7
    fi

    if [[ "$dry_run" == "true" ]]; then
        export BRIK_DRY_RUN="true"
    fi

    "$publish_fn" "${passthrough_args[@]}"
    return $?
}
