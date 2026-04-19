#!/usr/bin/env bash
# @module stages/container_scan
# @description Container scan stage - post-package container image scanning.
# Runs in the scanner image after the package stage produces an image.

# Container scan stage: scan a built container image for vulnerabilities.
# Usage: stages.container_scan <context_file>
stages.container_scan() {
    local context_file="$1"

    config.export_security_vars

    local image="${BRIK_SECURITY_CONTAINER_IMAGE:-}"

    if [[ -z "$image" ]]; then
        log.info "no container image configured - skipping container scan"
        context.set "$context_file" "BRIK_CONTAINER_SCAN_STATUS" "skipped"
        return 0
    fi

    log.info "container scan stage - scanning image: $image"

    local severity="${BRIK_SECURITY_CONTAINER_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"

    if ! declare -f security.run >/dev/null 2>&1; then
        brik.use "security"
    fi

    local result=0
    security.run "${BRIK_WORKSPACE}" --scans "container" --image "$image" --severity "$severity" || result=$?

    context.set_result "$context_file" "BRIK_CONTAINER_SCAN_STATUS" "$result"

    return "$result"
}
