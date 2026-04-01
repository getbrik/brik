#!/usr/bin/env bash
# @module stages/security
# @description Security stage - dependency, secret, and container scanning.

# Security stage: run configured security scans via brik-lib.
# Usage: stages.security <context_file>
stages.security() {
    local context_file="$1"

    config.export_security_vars

    if [[ "${BRIK_SECURITY_ENABLED:-false}" != "true" ]]; then
        log.info "security stage disabled - skipping"
        context.set "$context_file" "BRIK_SECURITY_STATUS" "skipped"
        return 0
    fi

    brik.use security

    log.info "security stage - running scans"

    local scan_args=()
    [[ -n "${BRIK_SECURITY_DEPENDENCY_SCAN:-}" ]] && scan_args+=(--dependency-scan "$BRIK_SECURITY_DEPENDENCY_SCAN")
    [[ -n "${BRIK_SECURITY_SECRET_SCAN:-}" ]] && scan_args+=(--secret-scan "$BRIK_SECURITY_SECRET_SCAN")
    [[ -n "${BRIK_SECURITY_CONTAINER_SCAN:-}" ]] && scan_args+=(--container-scan "$BRIK_SECURITY_CONTAINER_SCAN")
    [[ -n "${BRIK_SECURITY_SEVERITY_THRESHOLD:-}" ]] && scan_args+=(--severity "$BRIK_SECURITY_SEVERITY_THRESHOLD")

    security.run "${BRIK_WORKSPACE}" "${scan_args[@]}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_SECURITY_STATUS" "success"
    else
        context.set "$context_file" "BRIK_SECURITY_STATUS" "failed"
    fi

    return "$result"
}
