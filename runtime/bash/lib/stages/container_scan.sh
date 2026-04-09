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

    if ! declare -f security.container.run >/dev/null 2>&1; then
        local sec_container_path="${BASH_SOURCE[0]%/*}/../core/security/container.sh"
        if [[ -f "$sec_container_path" ]]; then
            # shellcheck source=../core/security/container.sh
            . "$sec_container_path"
        fi
    fi

    if ! declare -f security.container.run >/dev/null 2>&1; then
        log.warn "security.container module not available - skipping container scan"
        context.set "$context_file" "BRIK_CONTAINER_SCAN_STATUS" "skipped"
        return 0
    fi

    local severity="${BRIK_SECURITY_CONTAINER_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"
    local scan_args=("${BRIK_WORKSPACE}" --image "$image" --severity "$severity")

    security.container.run "${scan_args[@]}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_CONTAINER_SCAN_STATUS" "success"
    else
        context.set "$context_file" "BRIK_CONTAINER_SCAN_STATUS" "failed"
    fi

    return "$result"
}
