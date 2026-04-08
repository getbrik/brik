#!/usr/bin/env bash
# @module quality.deps
# @uses quality._tools
# @description Dependency vulnerability scanning via tool registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_DEPS_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_DEPS_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/_tools.sh"

# Register universal fallback scanners (stack-specific tools detected inline)
quality.tool.register deps osv-scanner osv-scanner "osv-scanner scan --format table ." 10
quality.tool.register deps grype       grype       "grype dir:{workspace}"              20

# Run dependency scanning on a workspace.
# Usage: quality.deps.run <workspace> [--severity <low|medium|high|critical>]
quality.deps.run() {
    local workspace="$1"
    shift
    local severity="high"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --severity) severity="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Tier 1: explicit command override
    if [[ -n "${BRIK_QUALITY_DEPS_COMMAND:-}" ]]; then
        log.info "scanning dependencies (command override): $BRIK_QUALITY_DEPS_COMMAND"
        (cd "$workspace" && eval "$BRIK_QUALITY_DEPS_COMMAND") || {
            log.error "dependency vulnerabilities found"
            return 10
        }
        log.info "dependency scan passed"
        return 0
    fi

    local scan_cmd=""

    # Stack-specific detection (unchanged)
    if [[ -f "${workspace}/package.json" ]]; then
        if command -v npm >/dev/null 2>&1; then
            scan_cmd="npm audit --audit-level=$severity"
        fi
    elif [[ -f "${workspace}/pyproject.toml" || -f "${workspace}/setup.py" ]]; then
        if command -v pip-audit >/dev/null 2>&1; then
            scan_cmd="pip-audit"
        elif command -v safety >/dev/null 2>&1; then
            scan_cmd="safety check"
        fi
    fi

    # Fallback: universal scanner via registry (replaces trivy)
    if [[ -z "$scan_cmd" ]]; then
        local resolved
        resolved="$(quality.tool.resolve deps)" || {
            log.warn "no dependency scanner available - skipping"
            return 0
        }
        log.info "scanning dependencies with ${resolved}"
        (cd "$workspace" && quality.tool.exec deps "$resolved" \
            workspace="$workspace" severity="${severity^^}") || {
            log.error "dependency vulnerabilities found"
            return 10
        }
        log.info "dependency scan passed"
        return 0
    fi

    log.info "scanning dependencies: $scan_cmd"
    (cd "$workspace" && eval "$scan_cmd") || {
        log.error "dependency vulnerabilities found"
        return 10
    }

    log.info "dependency scan passed"
    return 0
}
