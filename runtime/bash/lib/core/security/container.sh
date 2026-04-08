#!/usr/bin/env bash
# @module security.container
# @uses quality._tools
# @description Security-focused container image scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_CONTAINER_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_CONTAINER_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=../quality/_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../quality/_tools.sh"

# Register security container scanners
quality.tool.register sec_container grype  grype  "grype {image} --fail-on {severity}" 10
quality.tool.register sec_container dockle dockle "dockle {image}"                     20

# Run security container scan.
# Usage: security.container.run <workspace> [--image <image>] [--severity <threshold>]
security.container.run() {
    # shellcheck disable=SC2034
    local workspace="$1"
    shift
    local image="" severity="HIGH"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image) image="$2"; shift 2 ;;
            --severity) severity="${2^^}"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$image" ]]; then
        image="${BRIK_PROJECT_NAME:-project}:${BRIK_VERSION:-latest}"
    fi

    # Tier 1: BRIK_SECURITY_CONTAINER_SCAN_COMMAND
    if [[ -n "${BRIK_SECURITY_CONTAINER_SCAN_COMMAND:-}" ]]; then
        log.info "security container scan (command override): $BRIK_SECURITY_CONTAINER_SCAN_COMMAND"
        (cd "$workspace" && eval "$BRIK_SECURITY_CONTAINER_SCAN_COMMAND") || {
            log.error "security container vulnerabilities found in: $image"
            return 10
        }
        log.info "security container scan passed"
        return 0
    fi

    local resolved
    resolved="$(quality.tool.resolve sec_container)" || {
        log.warn "no security container scanner available (install grype) - skipping"
        return 0
    }

    log.info "security container scan with ${resolved}"
    quality.tool.exec sec_container "$resolved" \
        image="$image" severity="${severity,,}" || {
        log.error "security container vulnerabilities found in: $image"
        return 10
    }

    log.info "security container scan passed"
    return 0
}
