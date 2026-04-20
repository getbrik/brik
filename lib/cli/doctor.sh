#!/usr/bin/env bash
# @module cli.doctor
# @description CLI entrypoint for "brik doctor". Parses --workspace and
#   delegates the actual check suite to doctor.run (lib/core/doctor.sh).

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_DOCTOR_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_DOCTOR_LOADED=1

# cli.doctor.run - parse CLI args and run the prerequisite check suite.
# Usage: cli.doctor.run [--workspace <dir>]
# Exit codes: 0 if all checks pass, non-zero on the first failing check.
cli.doctor.run() {
    brik.use cli.helpers

    local workspace="."

    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    brik.use doctor
    doctor.run "${workspace}"
}
