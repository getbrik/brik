#!/usr/bin/env bash
# @module logging
# @description Structured logging API for the Brik runtime.
#
# Outputs to stderr in the format:
#   <ISO 8601 timestamp>  <LABEL>  <scope>  <message>
#
# Two-space separators (whitespace, no brackets). LABEL is left-padded to
# 5 chars so columns align across levels. When colors are enabled the
# WHOLE line is wrapped in the level color so a quick glance distinguishes
# OK / WARN / ERROR / SKIP / INFO / DEBUG lines.
#
# Levels (label / line color):
#   debug   -> DEBUG (dim)
#   info    -> INFO  (blue)
#   success -> OK    (green)
#   warn    -> WARN  (yellow)
#   error   -> ERROR (red)
#
# Respects BRIK_LOG_LEVEL (default: info). `success` filters as `info`.
# Scope is read from BRIK_LOG_SCOPE (set by stage.run).
#
# Color is enabled when stderr is a TTY or a known CI platform with ANSI
# rendering (GitLab, Jenkins). Disabled by NO_COLOR (no-color.org) or
# BRIK_LOG_NO_COLOR=1. Force-on for tests via BRIK_LOG_FORCE_COLOR=1.

# Guard against double-sourcing
[[ -n "${_BRIK_LOGGING_LOADED:-}" ]] && return 0
_BRIK_LOGGING_LOADED=1

# shellcheck source=../transverse/render.sh
. "${BASH_SOURCE[0]%/*}/../transverse/render.sh"

# Level constants (lower = more verbose)
readonly _BRIK_LOG_LEVEL_DEBUG=0
readonly _BRIK_LOG_LEVEL_INFO=1
readonly _BRIK_LOG_LEVEL_WARN=2
readonly _BRIK_LOG_LEVEL_ERROR=3

# ANSI color escapes for log levels. Resolved via render.color (force-on)
# at source time so the escape sequences themselves come from a single
# source of truth (render.sh); the per-call decision to *emit* them is
# kept inside this module via _log._color_enabled, which preserves the
# logging-specific overrides (BRIK_LOG_FORCE_COLOR / BRIK_LOG_NO_COLOR).
readonly _BRIK_C_RESET="$(BRIK_RENDER_FORCE_COLOR=1 render.color reset)"
readonly _BRIK_C_DIM="$(BRIK_RENDER_FORCE_COLOR=1 render.color dim)"
readonly _BRIK_C_RED="$(BRIK_RENDER_FORCE_COLOR=1 render.color red)"
readonly _BRIK_C_GREEN="$(BRIK_RENDER_FORCE_COLOR=1 render.color green)"
readonly _BRIK_C_YELLOW="$(BRIK_RENDER_FORCE_COLOR=1 render.color yellow)"
readonly _BRIK_C_BLUE="$(BRIK_RENDER_FORCE_COLOR=1 render.color blue)"

# Resolve the numeric threshold from BRIK_LOG_LEVEL.
# `success` maps to INFO so it filters identically.
_log._level_to_int() {
    case "${1:-info}" in
        debug)         printf '%d' "$_BRIK_LOG_LEVEL_DEBUG" ;;
        info|success)  printf '%d' "$_BRIK_LOG_LEVEL_INFO"  ;;
        warn)          printf '%d' "$_BRIK_LOG_LEVEL_WARN"  ;;
        error)         printf '%d' "$_BRIK_LOG_LEVEL_ERROR" ;;
        *)             printf '%d' "$_BRIK_LOG_LEVEL_INFO"  ;;
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

# Decide whether ANSI color escapes should be emitted on stderr.
# Order: FORCE_COLOR -> BRIK_LOG_NO_COLOR -> NO_COLOR -> TTY -> known CI.
_log._color_enabled() {
    [[ "${BRIK_LOG_FORCE_COLOR:-}" == "1" ]] && return 0
    [[ "${BRIK_LOG_NO_COLOR:-}" == "1" ]] && return 1
    [[ -n "${NO_COLOR:-}" ]] && return 1
    [[ -t 2 ]] && return 0
    [[ "${GITLAB_CI:-}" == "true" ]] && return 0
    [[ -n "${JENKINS_URL:-}" ]] && return 0
    return 1
}

# Map a logical level to its display label and cached ANSI escape.
# Sets two caller-visible variables: _LABEL and _COLOR.
#
# Delegates the level -> label+color-name mapping to render.sh's
# _render._level_meta (single source of truth shared with render.status).
# This module then resolves the color name to the cached escape constant
# (so per-call cost stays minimal -- no repeated render.color subshells).
_log._style_for() {
    local _LEVEL_LABEL _LEVEL_COLOR
    _render._level_meta "$1"
    _LABEL="$_LEVEL_LABEL"
    case "$_LEVEL_COLOR" in
        green)  _COLOR="$_BRIK_C_GREEN"  ;;
        red)    _COLOR="$_BRIK_C_RED"    ;;
        yellow) _COLOR="$_BRIK_C_YELLOW" ;;
        blue)   _COLOR="$_BRIK_C_BLUE"   ;;
        dim)    _COLOR="$_BRIK_C_DIM"    ;;
        *)      _COLOR=""                ;;
    esac
}

# Internal emitter - writes a formatted log line to stderr.
#
# Format:
#   <ts>  <LABEL:5>  <scope>  <message>
#
# Whitespace-separated (no brackets), label padded to 5 chars so columns
# align across all levels (longest labels are DEBUG/ERROR = 5). When
# colors are enabled, the *entire* line is wrapped in the level color
# so quick visual scanning distinguishes OK/WARN/ERROR/SKIP/INFO/DEBUG
# without parsing the label text.
_log._emit() {
    local level="$1"
    shift
    local message="$*"
    local scope="${BRIK_LOG_SCOPE:-brik}"
    local timestamp
    timestamp="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local _LABEL _COLOR
    _log._style_for "$level"
    # Pad LABEL to 5 chars (length of DEBUG / ERROR).
    local label_padded
    printf -v label_padded '%-5s' "$_LABEL"
    if [[ -n "$_COLOR" ]] && _log._color_enabled; then
        printf '%s%s  %s  %s  %s%s\n' \
            "$_COLOR" "$timestamp" "$label_padded" "$scope" "$message" "$_BRIK_C_RESET" >&2
    else
        printf '%s  %s  %s  %s\n' \
            "$timestamp" "$label_padded" "$scope" "$message" >&2
    fi
}

log.debug() {
    _log._should_log debug || return 0
    _log._emit debug "$@"
}

log.info() {
    _log._should_log info || return 0
    _log._emit info "$@"
}

log.success() {
    _log._should_log success || return 0
    _log._emit success "$@"
}

log.warn() {
    _log._should_log warn || return 0
    _log._emit warn "$@"
}

log.error() {
    _log._should_log error || return 0
    _log._emit error "$@"
}

# Resolve the log directory used by context.sh, pipeline-env.sh, report.sh,
# stage.sh and every other runtime module that needs to write under
# BRIK_LOG_DIR. Single source of truth for the precedence:
#   1. $BRIK_LOG_DIR (explicit override, always wins when non-empty)
#   2. ${BRIK_WORKSPACE}/.brik-logs (workspace-derived; the standard)
#   3. /tmp/brik/logs (ultimate fallback for pre-init contexts where
#      BRIK_WORKSPACE is not yet exported, e.g. Jenkins agent setup)
#
# Lives in logging.sh because it has no dependency beyond shell builtins
# and is loaded earlier than transverse/artifacts.sh in most modules.
_brik.log_dir._resolve() {
    if [[ -n "${BRIK_LOG_DIR:-}" ]]; then
        printf '%s' "$BRIK_LOG_DIR"
    elif [[ -n "${BRIK_WORKSPACE:-}" ]]; then
        printf '%s/.brik-logs' "$BRIK_WORKSPACE"
    else
        printf '/tmp/brik/logs'
    fi
}
