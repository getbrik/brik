#!/usr/bin/env bash
# @module cli.stage
# @description CLI entrypoint for "brik stage <name>". Executes a single
#   pipeline stage via the local wrapper (dev/debug verb).

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_STAGE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_STAGE_LOADED=1

# cli.stage.run - execute a single stage via the local wrapper.
# Usage: cli.stage.run <stage_name> [--config <path>] [--workspace <path>] [--dry-run]
cli.stage.run() {
    brik.use cli.helpers
    brik.use cli.local_runner

    local stage_name=""
    local config_path=""
    local workspace=""
    local dry_run=""

    if [[ $# -eq 0 ]]; then
        brik_error "'brik stage' requires a stage name"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    stage_name="$1"
    shift
    workspace="$(pwd)"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                brik_require_arg "--config" "${2-}" || return "$?"
                config_path="$2"
                shift 2
                ;;
            --workspace)
                brik_require_arg "--workspace" "${2-}" || return "$?"
                workspace="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    if [[ -z "$config_path" ]]; then
        config_path="${workspace}/${BRIK_DEFAULT_CONFIG}"
    fi

    export BRIK_PROJECT_DIR="${workspace}"
    export BRIK_WORKSPACE="${workspace}"
    export BRIK_CONFIG_FILE="${config_path}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${workspace}/.brik-logs}"
    mkdir -p "${BRIK_LOG_DIR}"

    # Activate dry-run only when the flag was passed. We never demote a
    # pre-existing BRIK_DRY_RUN=true exported by the caller's shell.
    [[ "$dry_run" == "true" ]] && export BRIK_DRY_RUN="true"

    cli.local_runner.setup_env || return "$?"

    cli.local_runner.runtime brik.local.run_stage "$stage_name"
}
