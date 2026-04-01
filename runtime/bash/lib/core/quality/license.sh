#!/usr/bin/env bash
# @module quality.license
# @description License compliance checking.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_LICENSE_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_LICENSE_LOADED=1

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

    if command -v license_finder >/dev/null 2>&1; then
        scan_cmd="license_finder"
        if [[ -n "$allowed" ]]; then
            scan_cmd="$scan_cmd --permitted-licenses=$allowed"
        fi
        if [[ -n "$denied" ]]; then
            scan_cmd="$scan_cmd --restricted-licenses=$denied"
        fi
    elif command -v trivy >/dev/null 2>&1; then
        scan_cmd="trivy fs --scanners license ."
    else
        log.warn "no license scanner available (install license_finder or trivy) - skipping"
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
