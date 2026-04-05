#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module stage
# @description Stage lifecycle orchestrator for the Brik runtime.
#
# stage.run is the central entry point for every stage in the fixed flow.
# It manages context, logging, hooks, execution, summary, and cleanup.
#
# stage.run MUST NOT:
#   - contain business logic
#   - call exit
#   - depend on set -e

# Guard against double-sourcing
[[ -n "${_BRIK_STAGE_LOADED:-}" ]] && return 0
_BRIK_STAGE_LOADED=1

# Source all runtime modules
_stage._load_runtime() {
    local runtime_dir="${BASH_SOURCE[0]%/*}"
    # shellcheck source=logging.sh
    [[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${runtime_dir}/logging.sh"
    # shellcheck source=error.sh
    [[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${runtime_dir}/error.sh"
    # shellcheck source=tools.sh
    [[ -z "${_BRIK_TOOLS_LOADED:-}" ]] && . "${runtime_dir}/tools.sh"
    # shellcheck source=context.sh
    [[ -z "${_BRIK_CONTEXT_LOADED:-}" ]] && . "${runtime_dir}/context.sh"
    # shellcheck source=hooks.sh
    [[ -z "${_BRIK_HOOKS_LOADED:-}" ]] && . "${runtime_dir}/hooks.sh"
    # shellcheck source=summary.sh
    [[ -z "${_BRIK_SUMMARY_LOADED:-}" ]] && . "${runtime_dir}/summary.sh"
    # shellcheck source=setup.sh
    [[ -z "${_BRIK_SETUP_LOADED:-}" ]] && . "${runtime_dir}/setup.sh"
}

_stage._load_runtime

# Create a log file for a stage. Prints the path on stdout.
stage.create_log_file() {
    local stage_name="$1"
    local log_dir="${BRIK_LOG_DIR:-/tmp/brik/logs}"
    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return 6
    }
    local log_file
    log_file="$(mktemp "${log_dir}/${stage_name}-XXXXXX")" || {
        log.error "cannot create log file for stage: $stage_name"
        return 6
    }
    mv "$log_file" "${log_file}.log" && log_file="${log_file}.log"
    printf '%s' "$log_file"
    return 0
}

# Execute a command while capturing all output to a log file.
# Preserves the command's exit status via PIPESTATUS.
stage.with_logging() {
    local log_file="$1"
    shift
    "$@" 2>&1 | tee -a "$log_file"
    return "${PIPESTATUS[0]}"
}

# Execute the stage logic function with proper scope.
stage.execute() {
    local stage_name="$1"
    local logic_function="$2"
    local context_file="$3"
    shift 3

    local previous_scope="${BRIK_LOG_SCOPE:-}"
    export BRIK_LOG_SCOPE="$stage_name"

    if ! declare -f "$logic_function" >/dev/null 2>&1; then
        log.error "logic function not defined: $logic_function"
        export BRIK_LOG_SCOPE="$previous_scope"
        return 2
    fi

    "$logic_function" "$context_file" "$@"
    local result=$?

    export BRIK_LOG_SCOPE="$previous_scope"
    return "$result"
}

# Cleanup after stage execution.
stage.cleanup() {
    local context_file="$1"
    local log_file="$2"
    hook.on_cleanup "${BRIK_LOG_SCOPE:-brik}" "$context_file" "$log_file" || true
    log.debug "stage cleanup complete"
    return 0
}

# Main entry point for stage execution.
# Usage: stage.run <stage_name> <logic_function> [args...]
stage.run() {
    local stage_name="$1"
    local logic_function="$2"
    shift 2
    local -a args=("$@")

    local context_file=""
    local log_file=""
    local exit_code=0

    log.info "starting stage: $stage_name"

    # Create execution context
    context_file="$(context.create "$stage_name")" || return 4
    log_file="$(stage.create_log_file "$stage_name")" || return 6
    context.set "$context_file" "BRIK_LOG_FILE" "$log_file" || return 6

    # Pre-stage hook (can abort)
    hook.pre_stage "$stage_name" "$context_file" "$log_file" || {
        exit_code=$?
        log.warn "pre-stage hook failed with code $exit_code, aborting stage"
        summary.build "$stage_name" "$context_file" "$log_file" "$exit_code" || true
        stage.cleanup "$context_file" "$log_file" || true
        return "$exit_code"
    }

    # Execute stage logic with logging
    stage.with_logging "$log_file" \
        stage.execute "$stage_name" "$logic_function" "$context_file" "${args[@]}"
    exit_code=$?

    # Record finish time in context
    context.set "$context_file" "BRIK_FINISHED_AT" "$(date +"%Y-%m-%dT%H:%M:%S%z")" || true

    # Success or failure hooks (best effort)
    if [[ $exit_code -eq 0 ]]; then
        log.info "stage $stage_name completed successfully"
        hook.on_success "$stage_name" "$context_file" "$log_file" || true
    else
        log.error "stage $stage_name failed with exit code $exit_code"
        hook.on_failure "$stage_name" "$context_file" "$log_file" "$exit_code" || true
    fi

    # Post-stage hook (best effort - does not override exit code)
    hook.post_stage "$stage_name" "$context_file" "$log_file" "$exit_code" || true

    # Summary and cleanup
    summary.build "$stage_name" "$context_file" "$log_file" "$exit_code" || true
    stage.cleanup "$context_file" "$log_file" || true

    return "$exit_code"
}
