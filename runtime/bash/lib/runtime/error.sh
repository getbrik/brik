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

# Default log directory - single source of truth for runtime modules
export BRIK_DEFAULT_LOG_DIR="/tmp/brik/logs"

# Exit code constants - exported for use by all brik-lib modules
#
#  0  OK              - success, no error
#  1  FAILURE         - generic/unspecified failure
#  2  INVALID_INPUT   - bad argument, missing required parameter, malformed value
#  3  MISSING_DEP     - required tool or dependency not found on PATH
#  4  INVALID_ENV     - environment misconfiguration (missing env var, wrong platform)
#  5  EXTERNAL_FAIL   - external command or service returned an error (npm, pip, API...)
#  6  IO_FAILURE      - filesystem error (cannot read/write/create file or directory)
#  7  CONFIG_ERROR    - brik.yml parse error, schema violation, or missing config key
#  8  TIMEOUT         - operation exceeded its time limit (reserved for runtime)
#  9  INTERRUPTED     - operation cancelled by signal or user (reserved for runtime)
# 10  CHECK_FAILED    - quality or security check did not meet threshold
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
export BRIK_EXIT_CHECK_FAILED=10

# Emit an error log and return the given code.
# Usage: error.raise <code> <message>
error.raise() {
    local code="$1"
    local message="$2"
    log.error "$message"
    return "$code"
}
