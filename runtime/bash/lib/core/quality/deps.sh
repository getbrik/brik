#!/usr/bin/env bash
# @module quality.deps
# @description Dependency vulnerability scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_DEPS_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_DEPS_LOADED=1

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

    # Fallback to trivy for any stack
    if [[ -z "$scan_cmd" ]]; then
        if command -v trivy >/dev/null 2>&1; then
            scan_cmd="trivy fs --scanners vuln --severity ${severity^^} ."
        else
            log.warn "no dependency scanner available - skipping"
            return 0
        fi
    fi

    log.info "scanning dependencies: $scan_cmd"
    (cd "$workspace" && eval "$scan_cmd") || {
        log.error "dependency vulnerabilities found"
        return 10
    }

    log.info "dependency scan passed"
    return 0
}
