#!/usr/bin/env bash
# @module security
# @uses security.deps security.secret_scan security.container
# @description Security stage facade. Delegates to dedicated security sub-modules.

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
        # Source security.deps module (skip if already defined, e.g. mocked)
        if ! declare -f security.deps.run >/dev/null 2>&1; then
            local sec_deps_path="${BASH_SOURCE[0]%/*}/security/deps.sh"
            if [[ -f "$sec_deps_path" ]]; then
                # shellcheck source=security/deps.sh
                . "$sec_deps_path"
            fi
        fi
        if declare -f security.deps.run >/dev/null 2>&1; then
            security.deps.run "$workspace" --severity "$severity" || failed=$((failed + 1))
        else
            log.warn "security.deps module not available - skipping dependency scan"
        fi
    fi

    if [[ "$secret_scan" == "true" ]]; then
        total=$((total + 1))
        # Source security.secret_scan module (skip if already defined, e.g. mocked)
        if ! declare -f security.secret_scan.run >/dev/null 2>&1; then
            local sec_secret_path="${BASH_SOURCE[0]%/*}/security/secret_scan.sh"
            if [[ -f "$sec_secret_path" ]]; then
                # shellcheck source=security/secret_scan.sh
                . "$sec_secret_path"
            fi
        fi
        if declare -f security.secret_scan.run >/dev/null 2>&1; then
            security.secret_scan.run "$workspace" || failed=$((failed + 1))
        else
            log.warn "security.secret_scan module not available - skipping secret scan"
        fi
    fi

    if [[ "$container_scan" == "true" ]]; then
        total=$((total + 1))
        # Source security.container module (skip if already defined, e.g. mocked)
        if ! declare -f security.container.run >/dev/null 2>&1; then
            local sec_container_path="${BASH_SOURCE[0]%/*}/security/container.sh"
            if [[ -f "$sec_container_path" ]]; then
                # shellcheck source=security/container.sh
                . "$sec_container_path"
            fi
        fi
        if declare -f security.container.run >/dev/null 2>&1; then
            local container_args=("$workspace")
            [[ -n "$image" ]] && container_args+=(--image "$image")
            container_args+=(--severity "$severity")
            security.container.run "${container_args[@]}" || failed=$((failed + 1))
        else
            log.warn "security.container module not available - skipping container scan"
        fi
    fi

    local passed=$((total - failed))
    log.info "security summary: $passed/$total scans passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        return 10
    fi
    return 0
}
