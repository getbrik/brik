#!/usr/bin/env bash
# @module cli.run
# @description CLI entrypoint for "brik run {stage|pipeline}". Sources the
#   local-wrapper and dispatches to brik.local.run_stage or run_pipeline.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_RUN_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_RUN_LOADED=1

# cli.run.run - dispatch "brik run <subcommand>".
# Usage: cli.run.run <stage|pipeline> [args...]
cli.run.run() {
    brik.use cli.helpers

    if [[ $# -eq 0 ]]; then
        brik_error "'brik run' requires a subcommand. Usage: brik run {stage|pipeline}"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    local subcmd="$1"
    shift

    case "${subcmd}" in
        stage)    cli.run.stage "$@" ;;
        pipeline) cli.run.pipeline "$@" ;;
        *)
            brik_usage_error "unknown run subcommand: ${subcmd}" || return "$?"
            ;;
    esac
}

# Source the local wrapper and run brik.local.setup with set +e so failures
# propagate via return code rather than aborting the shell.
_cli.run._setup_local_env() {
    local wrapper="${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
    pipeline.require_file "${wrapper}" || return "$?"
    # shellcheck source=/dev/null
    . "${wrapper}"

    local rc
    set +e
    brik.local.setup
    rc=$?
    set -e
    return "$rc"
}

# Run a command with set -e disabled; return its exit code.
_cli.run._runtime() {
    local rc
    set +e
    "$@"
    rc=$?
    set -e
    return "$rc"
}

# cli.run.stage - execute a single stage via the local wrapper.
# Usage: cli.run.stage <stage_name> [--config <path>] [--workspace <path>]
cli.run.stage() {
    brik.use cli.helpers

    local stage_name=""
    local config_path=""
    local workspace=""

    if [[ $# -eq 0 ]]; then
        brik_error "'brik run stage' requires a stage name"
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
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-/tmp/brik/logs}"
    mkdir -p "${BRIK_LOG_DIR}"

    _cli.run._setup_local_env || return "$?"

    _cli.run._runtime brik.local.run_stage "$stage_name"
}

# cli.run.pipeline - execute the full pipeline via the local wrapper.
# Usage: cli.run.pipeline [--config <path>] [--workspace <path>]
#        [--continue-on-error] [--with-release] [--with-package] [--with-deploy]
cli.run.pipeline() {
    brik.use cli.helpers

    local config_path=""
    local workspace=""
    local -a pipeline_flags=()

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
            --continue-on-error|--with-release|--with-package|--with-deploy)
                pipeline_flags+=("$1")
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
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-/tmp/brik/logs}"
    mkdir -p "${BRIK_LOG_DIR}"

    _cli.run._setup_local_env || return "$?"

    _cli.run._runtime brik.local.run_pipeline "${pipeline_flags[@]}"
}
