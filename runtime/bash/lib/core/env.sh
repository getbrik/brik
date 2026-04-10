#!/usr/bin/env bash
# @module env
# @description Environment management - load env files and validate variables.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_ENV_LOADED:-}" ]] && return 0
_BRIK_CORE_ENV_LOADED=1

# Load environment-specific variables.
# Usage: env.load <environment> [--config-dir <path>]
env.load() {
    local environment="$1"
    shift
    local config_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config-dir) config_dir="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    [[ -z "$config_dir" ]] && config_dir="${BRIK_PROJECT_DIR:-$(pwd)}/.brik/env"

    local env_file="${config_dir}/${environment}.env"

    if [[ ! -f "$env_file" ]]; then
        log.warn "environment file not found: $env_file"
        return 0
    fi

    log.info "loading environment: $environment from $env_file"
    # shellcheck source=/dev/null
    . "$env_file" || {
        log.error "failed to source environment file: $env_file"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    return 0
}

# Validate that required environment variables are set.
# Usage: env.require <var1> [var2] ...
env.require() {
    local var
    for var in "$@"; do
        if [[ -z "${!var:-}" ]]; then
            log.error "required environment variable not set: $var"
            return "$BRIK_EXIT_INVALID_ENV"
        fi
    done
    return 0
}
