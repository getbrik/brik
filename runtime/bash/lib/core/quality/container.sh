#!/usr/bin/env bash
# @module quality.container
# @description Container image vulnerability scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_CONTAINER_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_CONTAINER_LOADED=1

# Scan a container image for vulnerabilities.
# Usage: quality.container.run <workspace> [--image <image>] [--severity <threshold>]
quality.container.run() {
    local workspace="$1"
    shift
    local image="" severity="HIGH"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image) image="$2"; shift 2 ;;
            --severity) severity="${2^^}"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$image" ]]; then
        image="${BRIK_PROJECT_NAME:-project}:${BRIK_VERSION:-latest}"
    fi

    local scan_cmd=""
    if command -v trivy >/dev/null 2>&1; then
        scan_cmd="trivy image --severity $severity $image"
    elif command -v grype >/dev/null 2>&1; then
        scan_cmd="grype $image"
    else
        log.warn "no container scanner available (install trivy or grype) - skipping"
        return 0
    fi

    log.info "scanning container image: $scan_cmd"
    eval "$scan_cmd" || {
        log.error "container vulnerabilities found in: $image"
        return 10
    }

    log.info "container scan passed"
    return 0
}
