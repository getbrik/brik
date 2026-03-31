#!/usr/bin/env bash
# @module tools
# @description Dependency validation helpers for the Brik runtime.

# Guard against double-sourcing
[[ -n "${_BRIK_TOOLS_LOADED:-}" ]] && return 0
_BRIK_TOOLS_LOADED=1

# Source logging if not already loaded
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"

# Check that a tool is available on PATH.
# Returns 0 if found, BRIK_EXIT_MISSING_DEP (3) if not.
runtime.require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        log.error "required tool not found: $tool"
        return 3
    fi
    return 0
}

# Check that a file exists.
# Returns 0 if found, BRIK_EXIT_IO_FAILURE (6) if not.
runtime.require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        log.error "required file not found: $path"
        return 6
    fi
    return 0
}

# Check that a directory exists.
# Returns 0 if found, BRIK_EXIT_IO_FAILURE (6) if not.
runtime.require_dir() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        log.error "required directory not found: $path"
        return 6
    fi
    return 0
}
