#!/usr/bin/env bash
# @module security.license
# @uses quality._tools
# @description Security-focused license compliance checking.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_LICENSE_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_LICENSE_LOADED=1

# Load tool registry
brik.use "quality._tools"

# Register license scanners (license_finder handled inline for conditional flags)
quality.tool.register sec_license syft     syft     "syft scan . -o spdx-json" 20
quality.tool.register sec_license scancode scancode "scancode --license --only-findings ." 30

# Run license compliance check.
# Usage: security.license.run <workspace>
security.license.run() {
    local workspace="$1"
    shift

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    local allowed="${BRIK_SECURITY_LICENSE_ALLOWED:-}"
    local denied="${BRIK_SECURITY_LICENSE_DENIED:-}"

    # license_finder: add permitted/restricted licenses, then check action_items
    if command -v license_finder >/dev/null 2>&1; then
        log.info "checking licenses with license_finder"
        (
            cd "$workspace"
            # Add permitted licenses from config (comma-separated -> individual adds)
            if [[ -n "$allowed" ]]; then
                local IFS=','
                for lic in $allowed; do
                    # best-effort: add is idempotent, may warn on duplicates
                    license_finder permitted_licenses add "$lic" 2>/dev/null || true
                done
            fi
            # Add restricted licenses from config
            if [[ -n "$denied" ]]; then
                local IFS=','
                for lic in $denied; do
                    license_finder restricted_licenses add "$lic" 2>/dev/null || true  # same as above
                done
            fi
            # Check for unapproved dependencies
            license_finder action_items
        ) || {
            log.error "license violations found"
            return "$BRIK_EXIT_CHECK_FAILED"
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
        return "$BRIK_EXIT_CHECK_FAILED"
    }
    log.info "license check passed"
    return 0
}
