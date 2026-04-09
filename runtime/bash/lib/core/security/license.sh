#!/usr/bin/env bash
# @module security.license
# @uses quality._tools
# @description Security-focused license compliance checking.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_LICENSE_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_LICENSE_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=../quality/_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../quality/_tools.sh"

# Register license scanners (license_finder handled inline for conditional flags)
quality.tool.register sec_license syft     syft     "syft scan . -o spdx-json" 20
quality.tool.register sec_license scancode scancode "scancode --license --only-findings ." 30

# Run license compliance check.
# Usage: security.license.run <workspace>
security.license.run() {
    local workspace="$1"
    shift

    runtime.require_dir "$workspace" || return 6

    local allowed="${BRIK_SECURITY_LICENSE_ALLOWED:-}"
    local denied="${BRIK_SECURITY_LICENSE_DENIED:-}"

    # license_finder handled inline (conditional --permitted/--restricted flags)
    if command -v license_finder >/dev/null 2>&1; then
        local scan_cmd="license_finder action_items"
        if [[ -n "$allowed" ]]; then
            # Convert comma-separated to space-separated for license_finder
            local allowed_args="${allowed//,/ }"
            scan_cmd="$scan_cmd --permitted-licenses $allowed_args"
        fi
        if [[ -n "$denied" ]]; then
            local denied_args="${denied//,/ }"
            scan_cmd="$scan_cmd --restricted-licenses $denied_args"
        fi
        log.info "checking licenses: $scan_cmd"
        (cd "$workspace" && eval "$scan_cmd") || {
            log.error "license violations found"
            return 10
        }
        log.info "license check passed"
        return 0
    fi

    # Fallback via registry (syft, scancode)
    local resolved
    resolved="$(quality.tool.resolve sec_license)" || {
        log.warn "no license scanner available (install license_finder or syft) - skipping"
        return 0
    }
    log.info "checking licenses with ${resolved}"
    (cd "$workspace" && quality.tool.exec sec_license "$resolved") || {
        log.error "license violations found"
        return 10
    }
    log.info "license check passed"
    return 0
}
