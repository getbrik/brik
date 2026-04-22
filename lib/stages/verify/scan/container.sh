#!/usr/bin/env bash
# @module verify.scan.container
# @uses transverse.tools
# @description Security-focused container image scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_SCAN_CONTAINER_LOADED:-}" ]] && return 0
_BRIK_VERIFY_SCAN_CONTAINER_LOADED=1

# Load tool registry
brik.use transverse.tools

# Register security container scanners
transverse.tools.register sec_container grype  grype  "grype {image} --fail-on {severity}" 10
transverse.tools.register sec_container dockle dockle "dockle {image}"                     20

# Run security container scan.
# Usage: verify.scan.container.run <workspace> [--image <image>] [--severity <threshold>]
verify.scan.container.run() {
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

    # Use config vars as fallback for image and severity
    if [[ -z "$image" ]]; then
        image="${BRIK_SECURITY_CONTAINER_IMAGE:-}"
    fi
    if [[ -z "$image" ]]; then
        image="${BRIK_PROJECT_NAME:-project}:${BRIK_APP_VERSION:-${BRIK_COMMIT_SHORT_SHA:-latest}}"
    fi

    if [[ -n "${BRIK_SECURITY_CONTAINER_SEVERITY:-}" && "$severity" == "HIGH" ]]; then
        severity="${BRIK_SECURITY_CONTAINER_SEVERITY^^}"
    fi

    local resolved
    resolved="$(transverse.tools.resolve sec_container)" || {
        log.warn "no security container scanner available (install grype) - skipping"
        return 0
    }

    log.info "security container scan with ${resolved}"
    transverse.tools.exec sec_container "$resolved" \
        image="$image" severity="${severity,,}" || {
        log.error "security container vulnerabilities found in: $image"
        return "$BRIK_EXIT_CHECK_FAILED"
    }

    log.info "security container scan passed"
    return 0
}
