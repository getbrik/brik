#!/usr/bin/env bash
# @module cli.helpers
# @description Shared CLI primitives (print, error, hint, usage guards).
#   Used by bin/brik itself and by per-command modules under lib/cli/.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_HELPERS_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_HELPERS_LOADED=1

brik_print() {
    printf '%s\n' "$1"
}

brik_error() {
    printf 'error: %s\n' "$1" >&2
}

brik_hint() {
    printf 'hint: %s\n' "$1" >&2
}

# brik_usage_error - print an error, remind the user of `brik help`, return
# BRIK_EXIT_INVALID_INPUT. Used by every cmd_* option parser.
brik_usage_error() {
    brik_error "$1"
    brik_error "Run 'brik help' for usage."
    return "${BRIK_EXIT_INVALID_INPUT}"
}

# brik_require_arg - guard that an option has a non-empty value.
# Usage: brik_require_arg --flag "${2-}" || return $?
brik_require_arg() {
    local opt="$1"
    local val="${2-}"
    if [[ -z "${val}" ]]; then
        brik_error "${opt} requires a value"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi
}

# _brik_detect_install_method - classify the Brik install source.
# Used by cli.version and cli.self_update to pick display/update strategy.
# Prints one of: brew, source, git, unknown.
_brik_detect_install_method() {
    if command -v brew >/dev/null 2>&1 && brew list brik >/dev/null 2>&1; then
        printf 'brew'
    elif [[ -d "${BRIK_HOME}/.git" ]]; then
        if [[ "${BRIK_HOME}" != "${HOME}/.brik" ]]; then
            printf 'source'
        else
            printf 'git'
        fi
    else
        printf 'unknown'
    fi
}
