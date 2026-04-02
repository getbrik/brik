#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module error
# @description Error helpers and exit code constants for the Brik runtime.
#
# Functions use return codes, never exit.

# Guard against double-sourcing
[[ -n "${_BRIK_ERROR_LOADED:-}" ]] && return 0
_BRIK_ERROR_LOADED=1

# Source logging if not already loaded
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"

# Exit code constants - exported for use by all brik-lib modules
export BRIK_EXIT_OK=0
export BRIK_EXIT_FAILURE=1
export BRIK_EXIT_INVALID_INPUT=2
export BRIK_EXIT_MISSING_DEP=3
export BRIK_EXIT_INVALID_ENV=4
export BRIK_EXIT_EXTERNAL_FAIL=5
export BRIK_EXIT_IO_FAILURE=6
export BRIK_EXIT_CONFIG_ERROR=7
export BRIK_EXIT_TIMEOUT=8
export BRIK_EXIT_INTERRUPTED=9

# Emit an error log and return the given code.
# Usage: error.raise <code> <message>
error.raise() {
    local code="$1"
    local message="$2"
    log.error "$message"
    return "$code"
}
