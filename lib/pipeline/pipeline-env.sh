#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module pipeline-env
# @description Cross-stage pipeline environment variable sharing.
#
# Manages a shared KEY=VALUE file ($BRIK_LOG_DIR/pipeline.env) that persists
# business variables across stages. Append-only -- last write wins on source.

# Guard against double-sourcing
[[ -n "${_BRIK_PIPELINE_ENV_LOADED:-}" ]] && return 0
_BRIK_PIPELINE_ENV_LOADED=1

# Source dependencies
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"

# Initialize the pipeline environment file.
# Exports BRIK_PIPELINE_ENV and creates the file if it does not exist.
# Returns 0 on success, BRIK_EXIT_IO_FAILURE on filesystem error.
pipeline.env.init() {
    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"

    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    export BRIK_PIPELINE_ENV="${log_dir}/pipeline.env"

    if [[ ! -f "$BRIK_PIPELINE_ENV" ]]; then
        : > "$BRIK_PIPELINE_ENV" || {
            log.error "cannot create pipeline env file: $BRIK_PIPELINE_ENV"
            return "$BRIK_EXIT_IO_FAILURE"
        }
    fi

    log.debug "pipeline env initialized: $BRIK_PIPELINE_ENV"
    return "$BRIK_EXIT_OK"
}

# Append a key-value pair to the pipeline environment file.
# Usage: pipeline.env.set <key> <value>
# Returns 0 on success, BRIK_EXIT_IO_FAILURE on filesystem error.
pipeline.env.set() {
    local key="$1"
    local value="$2"

    if [[ -z "${BRIK_PIPELINE_ENV:-}" ]]; then
        log.error "pipeline env not initialized -- call pipeline.env.init first"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    # Use %q so values containing newlines, quotes, or shell metachars
    # remain a single safe assignment when pipeline.env.load sources the
    # file. Without this, a multi-line CI variable would land as a
    # second bare line that bash tries to execute as a command.
    printf '%s=%q\n' "$key" "$value" >> "$BRIK_PIPELINE_ENV" || {
        log.error "cannot write to pipeline env file: $BRIK_PIPELINE_ENV"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    log.debug "pipeline env set: ${key}=${value}"
    return "$BRIK_EXIT_OK"
}

# Load all variables from the pipeline environment file into the current shell.
# No-op if the file does not exist. Last write wins for duplicate keys.
# Returns 0 always.
pipeline.env.load() {
    if [[ -z "${BRIK_PIPELINE_ENV:-}" || ! -f "${BRIK_PIPELINE_ENV}" ]]; then
        return "$BRIK_EXIT_OK"
    fi

    local line_count
    line_count="$(wc -l < "$BRIK_PIPELINE_ENV")"

    set -a
    # shellcheck source=/dev/null
    . "$BRIK_PIPELINE_ENV"
    set +a

    log.debug "pipeline env loaded: ${line_count} lines from $BRIK_PIPELINE_ENV"
    return "$BRIK_EXIT_OK"
}
