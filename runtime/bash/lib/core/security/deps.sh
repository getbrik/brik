#!/usr/bin/env bash
# @module security.deps
# @uses quality._tools
# @description Security-focused dependency vulnerability scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_DEPS_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_DEPS_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=../quality/_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../quality/_tools.sh"

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

    # Tier 2: BRIK_SECURITY_DEPS_TOOL
    local dep_tool="${BRIK_SECURITY_DEPS_TOOL:-}"
    if [[ -n "$dep_tool" ]]; then
        if command -v "$dep_tool" >/dev/null 2>&1; then
            log.info "security dependency scan with tool: $dep_tool"
            (cd "$workspace" && "$dep_tool" .) || {
                log.error "security dependency vulnerabilities found"
                return 10
            }
            log.info "security dependency scan passed"
            return 0
        else
            log.error "security dependency scan tool not found: $dep_tool"
            return 3
        fi
    fi

    # Tier 3: auto-detect via registry
    local resolved
    resolved="$(quality.tool.resolve sec_deps)" || {
        log.warn "no security dependency scanner available - skipping"
        return 0
    }
    log.info "security dependency scan with ${resolved}"
    (cd "$workspace" && quality.tool.exec sec_deps "$resolved" \
        workspace="$workspace" severity="${severity^^}") || {
        log.error "security dependency vulnerabilities found"
        return 10
    }
    log.info "security dependency scan passed"
    return 0
}
