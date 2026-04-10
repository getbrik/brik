#!/usr/bin/env bash
# @module security.deps
# @uses quality._tools security._scan
# @description Security-focused dependency vulnerability scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_DEPS_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_DEPS_LOADED=1

# Load tool registry and common scan helper
brik.use "quality._tools"
brik.use "security._scan"

# Register security dependency scanners (sec_ prefix avoids collision with quality.deps)
quality.tool.register sec_deps osv-scanner osv-scanner "osv-scanner scan --format table ." 10
quality.tool.register sec_deps grype       grype       "grype dir:{workspace}"              20

# Run security dependency scan on a workspace.
# Usage: security.deps.run <workspace> [--severity <threshold>]
security.deps.run() {
    local workspace="$1"
    shift
    local severity="high"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --severity) severity="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Tier 1: BRIK_SECURITY_DEPS_COMMAND
    if [[ -n "${BRIK_SECURITY_DEPS_COMMAND:-}" ]]; then
        log.info "security dependency scan (command override): $BRIK_SECURITY_DEPS_COMMAND"
        (cd "$workspace" && eval "$BRIK_SECURITY_DEPS_COMMAND") || {
            log.error "security dependency vulnerabilities found"
            return 10
        }
        log.info "security dependency scan passed"
        return 0
    fi

    # Tier 2+3: resolve via tool registry
    local tool="${BRIK_SECURITY_DEPS_TOOL:-}"
    local resolve_args=(sec_deps)
    [[ -n "$tool" ]] && resolve_args+=(--tool "$tool")

    local resolved
    resolved="$(quality.tool.resolve "${resolve_args[@]}")" || {
        local rc=$?
        if [[ $rc -eq 3 ]]; then
            log.error "security dependency scan tool not found: $tool"
            return 3
        elif [[ $rc -eq 7 ]]; then
            log.error "unknown security dependency scan tool: $tool"
            return 7
        fi
        log.warn "no security dependency scanner available - skipping"
        return 0
    }

    log.info "security dependency scan with $resolved"
    local scan_output=""
    scan_output="$(cd "$workspace" && quality.tool.exec sec_deps "$resolved" \
        workspace="$workspace" severity="${severity^^}" 2>&1)" || {
        # osv-scanner returns non-zero when no package sources found
        if echo "$scan_output" | grep -qi "no package sources found"; then
            log.warn "no package sources found for $resolved - skipping"
            return 0
        fi
        log.error "security dependency vulnerabilities found"
        return 10
    }
    log.info "security dependency scan passed"
    return 0
}
