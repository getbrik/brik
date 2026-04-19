#!/usr/bin/env bash
# @module logging
# @description Structured logging API for the Brik runtime.
#
# Outputs to stderr in the format:
#   <ISO 8601 timestamp> [<LEVEL>] [<scope>] <message>
#
# Respects BRIK_LOG_LEVEL (default: info).
# Scope is read from BRIK_LOG_SCOPE (set by stage.run).

# Guard against double-sourcing
[[ -n "${_BRIK_LOGGING_LOADED:-}" ]] && return 0
_BRIK_LOGGING_LOADED=1

# Level constants (lower = more verbose)
readonly _BRIK_LOG_LEVEL_DEBUG=0
readonly _BRIK_LOG_LEVEL_INFO=1
readonly _BRIK_LOG_LEVEL_WARN=2
readonly _BRIK_LOG_LEVEL_ERROR=3

# Resolve the numeric threshold from BRIK_LOG_LEVEL
_log._level_to_int() {
    case "${1:-info}" in
        debug) printf '%d' "$_BRIK_LOG_LEVEL_DEBUG" ;;
        info)  printf '%d' "$_BRIK_LOG_LEVEL_INFO"  ;;
        warn)  printf '%d' "$_BRIK_LOG_LEVEL_WARN"  ;;
        error) printf '%d' "$_BRIK_LOG_LEVEL_ERROR" ;;
        *)     printf '%d' "$_BRIK_LOG_LEVEL_INFO"  ;;
    esac
}

# Check whether a message at the given level should be emitted.
# Returns 0 (true) if it should, 1 (false) otherwise.
_log._should_log() {
    local msg_level="$1"
    local threshold
    threshold="$(_log._level_to_int "${BRIK_LOG_LEVEL:-info}")"
    local msg_int
    msg_int="$(_log._level_to_int "$msg_level")"
    [[ "$msg_int" -ge "$threshold" ]]
}

# Internal emitter - writes a formatted log line to stderr.
_log._emit() {
    local level="$1"
    shift
    local message="$*"
    local scope="${BRIK_LOG_SCOPE:-brik}"
    local timestamp
    timestamp="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local level_upper
    level_upper="$(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')"
    printf '%s [%s] [%s] %s\n' "$timestamp" "$level_upper" "$scope" "$message" >&2
}

log.debug() {
    _log._should_log debug || return 0
    _log._emit debug "$@"
}

log.info() {
    _log._should_log info || return 0
    _log._emit info "$@"
}

log.warn() {
    _log._should_log warn || return 0
    _log._emit warn "$@"
}

log.error() {
    _log._should_log error || return 0
    _log._emit error "$@"
}
