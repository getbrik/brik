#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module context
# @description Execution context management for the Brik runtime.
#
# The context is a flat KEY=VALUE file passed through the stage lifecycle.
# This avoids hidden global mutable state.

# Guard against double-sourcing
[[ -n "${_BRIK_CONTEXT_LOADED:-}" ]] && return 0
_BRIK_CONTEXT_LOADED=1

# Source dependencies
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"

# Create a new context file for a stage and print its path on stdout.
# Populates default keys from the environment.
# Returns 0 on success, 6 on IO failure.
context.create() {
    local stage_name="$1"
    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
    local context_file

    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    context_file="$(mktemp "${log_dir}/context-${stage_name}-XXXXXX")" || {
        log.error "cannot create context file"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local run_id
    run_id="$(date +%s)-$$"

    # Write default keys
    {
        printf 'BRIK_STAGE_NAME=%s\n' "$stage_name"
        printf 'BRIK_STAGE_ID=%s-%s\n' "$stage_name" "$run_id"
        printf 'BRIK_RUN_ID=%s\n' "$run_id"
        printf 'BRIK_WORKSPACE=%s\n' "${BRIK_WORKSPACE:-$(pwd)}"
        printf 'BRIK_LOG_DIR=%s\n' "$log_dir"
        printf 'BRIK_PLATFORM=%s\n' "${BRIK_PLATFORM:-local}"
        printf 'BRIK_PROJECT_DIR=%s\n' "${BRIK_PROJECT_DIR:-$(pwd)}"
        printf 'BRIK_CONFIG_FILE=%s\n' "${BRIK_CONFIG_FILE:-brik.yml}"
        printf 'BRIK_STARTED_AT=%s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")"
    } > "$context_file" || {
        log.error "cannot write to context file: $context_file"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    log.debug "context created: $context_file"
    printf '%s' "$context_file"
    return 0
}

# Get a value from the context file.
# Prints the value on stdout. Returns 1 if key not found.
context.get() {
    local context_file="$1"
    local key="$2"
    local line

    line="$(grep -m1 "^${key}=" "$context_file" 2>/dev/null)" || return "$BRIK_EXIT_FAILURE"
    printf '%s' "${line#*=}"
    return 0
}

# Set a value in the context file (add or replace).
# Returns 0 on success, 6 on IO failure.
context.set() {
    local context_file="$1"
    local key="$2"
    local value="$3"

    if grep -q "^${key}=" "$context_file" 2>/dev/null; then
        # Replace existing key - use a temp file for safety
        local tmp
        tmp="$(mktemp)" || return "$BRIK_EXIT_IO_FAILURE"
        sed "s|^${key}=.*|${key}=${value}|" "$context_file" > "$tmp" || {
            rm -f "$tmp"
            return "$BRIK_EXIT_IO_FAILURE"
        }
        mv "$tmp" "$context_file" || return "$BRIK_EXIT_IO_FAILURE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$context_file" || return "$BRIK_EXIT_IO_FAILURE"
    fi
    return 0
}

# Set a status key based on an exit code.
# Maps 0 -> "success", non-zero -> "failed".
# Usage: context.set_result <context_file> <key> <exit_code>
context.set_result() {
    local context_file="$1"
    local key="$2"
    local exit_code="$3"

    if [[ "$exit_code" -eq 0 ]]; then
        context.set "$context_file" "$key" "success"
    else
        context.set "$context_file" "$key" "failed"
    fi
}

# Check whether a key exists in the context file.
# Returns 0 if found, 1 otherwise.
context.exists() {
    local context_file="$1"
    local key="$2"
    grep -q "^${key}=" "$context_file" 2>/dev/null
}
