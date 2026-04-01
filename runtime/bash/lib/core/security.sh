#!/usr/bin/env bash
# @module security
# @uses quality.deps quality.sast quality.container
# @description Security stage facade. Composes quality sub-modules for security scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_LOADED=1

# Run security scans on a workspace.
# Usage: security.run <workspace> [--dependency-scan <true|false>]
#        [--secret-scan <true|false>] [--container-scan <true|false>]
#        [--severity <threshold>] [--image <image>]
security.run() {
    local workspace="$1"
    shift
    local dep_scan="true" secret_scan="true" container_scan="false"
    local severity="high" image=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dependency-scan) dep_scan="$2"; shift 2 ;;
            --secret-scan) secret_scan="$2"; shift 2 ;;
            --container-scan) container_scan="$2"; shift 2 ;;
            --severity) severity="$2"; shift 2 ;;
            --image) image="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    log.info "running security scans (deps=$dep_scan, secrets=$secret_scan, container=$container_scan)"

    local failed=0 total=0

    if [[ "$dep_scan" == "true" ]]; then
        total=$((total + 1))
        brik.use "quality.deps" 2>/dev/null || true
        if declare -f quality.deps.run >/dev/null 2>&1; then
            quality.deps.run "$workspace" --severity "$severity" || failed=$((failed + 1))
        else
            log.warn "quality.deps module not available - skipping dependency scan"
        fi
    fi

    if [[ "$secret_scan" == "true" ]]; then
        total=$((total + 1))
        brik.use "quality.sast" 2>/dev/null || true
        if declare -f quality.sast.run >/dev/null 2>&1; then
            quality.sast.run "$workspace" --tool trivy || failed=$((failed + 1))
        else
            log.warn "quality.sast module not available - skipping secret scan"
        fi
    fi

    if [[ "$container_scan" == "true" ]]; then
        total=$((total + 1))
        brik.use "quality.container" 2>/dev/null || true
        if declare -f quality.container.run >/dev/null 2>&1; then
            local container_args=("$workspace")
            [[ -n "$image" ]] && container_args+=(--image "$image")
            container_args+=(--severity "$severity")
            quality.container.run "${container_args[@]}" || failed=$((failed + 1))
        else
            log.warn "quality.container module not available - skipping container scan"
        fi
    fi

    local passed=$((total - failed))
    log.info "security summary: $passed/$total scans passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        return 10
    fi
    return 0
}
