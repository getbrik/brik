#!/usr/bin/env bash
# @module quality.license
# @uses quality._tools
# @description License compliance checking via tool registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_LICENSE_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_LICENSE_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/_tools.sh"

# Register license scanners (license_finder handled inline for conditional flags)
quality.tool.register license syft     syft     "syft scan . -o spdx-json" 20
quality.tool.register license scancode scancode "scancode --license --only-findings ." 30

# Run license compliance check.
# Usage: quality.license.run <workspace> [--allowed <licenses>] [--denied <licenses>]
quality.license.run() {
    local workspace="$1"
    shift
    local allowed="" denied=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --allowed) allowed="$2"; shift 2 ;;
            --denied) denied="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    local scan_cmd=""

    # license_finder handled inline (conditional --permitted/--restricted flags)
    if command -v license_finder >/dev/null 2>&1; then
        scan_cmd="license_finder"
        if [[ -n "$allowed" ]]; then
            scan_cmd="$scan_cmd --permitted-licenses=$allowed"
        fi
        if [[ -n "$denied" ]]; then
            scan_cmd="$scan_cmd --restricted-licenses=$denied"
        fi
    else
        # Fallback via registry (syft, scancode)
        local resolved
        resolved="$(quality.tool.resolve license)" || {
            log.warn "no license scanner available (install license_finder or syft) - skipping"
            return 0
        }
        log.info "checking licenses with ${resolved}"
        (cd "$workspace" && quality.tool.exec license "$resolved") || {
            log.error "license violations found"
            return 10
        }
        log.info "license check passed"
        return 0
    fi

    log.info "checking licenses: $scan_cmd"
    (cd "$workspace" && eval "$scan_cmd") || {
        log.error "license violations found"
        return 10
    }

    log.info "license check passed"
    return 0
}
