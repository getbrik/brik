#!/usr/bin/env bash
# @module deploy
# @uses env
# @description Deploy dispatcher for brik-lib.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_LOADED=1

# Run a deployment.
# Usage: deploy.run --target <k8s|compose|ssh|helm|gitops> --env <environment>
#        [--dry-run]
deploy.run() {
    local target="" environment="" dry_run="${BRIK_DRY_RUN:-}"
    local -a passthrough_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target) target="$2"; shift 2 ;;
            --env) environment="$2"; shift 2 ;;
            --dry-run) dry_run="true"; passthrough_args+=(--dry-run); shift ;;
            *) passthrough_args+=("$1"); shift ;;
        esac
    done

    if [[ -z "$target" ]]; then
        log.error "deploy target is required (--target)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Load environment if specified
    if [[ -n "$environment" ]]; then
        if declare -f env.load >/dev/null 2>&1; then
            env.load "$environment" || return $?
        fi
    fi

    log.info "deploying with target: $target"

    # Load and delegate to target-specific module
    brik.use "deploy.${target}" || {
        log.error "unsupported deploy target: $target"
        return "$BRIK_EXIT_CONFIG_ERROR"
    }

    local deploy_fn="deploy.${target}.run"
    if ! declare -f "$deploy_fn" >/dev/null 2>&1; then
        log.error "deploy function not found: $deploy_fn"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if [[ "$dry_run" == "true" ]]; then
        export BRIK_DRY_RUN="true"
    fi

    "$deploy_fn" "${passthrough_args[@]}"
    return $?
}
