#!/usr/bin/env bash
# @module quality.container
# @uses quality._tools
# @description Container image vulnerability scanning via tool registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_CONTAINER_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_CONTAINER_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/_tools.sh"

# Register container scanners (priority: lower = preferred)
quality.tool.register container grype  grype  "grype {image} --fail-on {severity}" 10
quality.tool.register container dockle dockle "dockle {image}"                     20

# Scan a container image for vulnerabilities.
# Usage: quality.container.run <workspace> [--image <image>] [--severity <threshold>]
quality.container.run() {
    # workspace is part of the uniform quality.*.run <workspace> API but unused here
    # shellcheck disable=SC2034
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

    local resolved
    resolved="$(quality.tool.resolve container)" || {
        log.warn "no container scanner available (install grype) - skipping"
        return 0
    }

    log.info "scanning container image with ${resolved}"
    quality.tool.exec container "$resolved" \
        image="$image" severity="${severity,,}" || {
        log.error "container vulnerabilities found in: $image"
        return 10
    }

    log.info "container scan passed"
    return 0
}
